(in-package #:nshell/spec)
(defparameter *probe-fixture-path*
    (merge-pathnames #p"docs/design/conformance/language-probes-v0.7.0.json"
                     (asdf:system-source-directory "nshell")))
  (defvar *probe-fixture-cache* nil)
  (defvar *l7-rows* nil)

  (defun %read-probe-fixture ()
    (with-open-file (stream *probe-fixture-path*
                            :direction :input
                            :external-format :utf-8)
      (json-kit:read-json stream :object-type :alist :array-type :list)))

  (defun %probe-fixture ()
    (or *probe-fixture-cache*
        (setf *probe-fixture-cache* (%read-probe-fixture))))

  (defun %fixture-cases ()
    (cdr (assoc "cases" (%probe-fixture) :test #'string=)))

  (defun %fixture-case (id)
    (or (find id (%fixture-cases)
              :key (lambda (case) (cdr (assoc "id" case :test #'string=)))
              :test #'string=)
        (error "No language-probe fixture case named ~a" id)))

  (defun %field (object key)
    (cdr (assoc key object :test #'string=)))

  (defun %required-nshell-bin ()
    (or (uiop:getenv "NSHELL_BIN")
        (error "NSHELL_BIN must name the nshell script-mode executable")))

  (defun %required-single-bin-path ()
    (let ((path (uiop:getenv "PATH")))
      (unless (and path
                   (not (find #\: path))
                   (uiop:directory-exists-p path))
        (error "t/spec requires PATH to name one fixed bin directory"))
      path))

  (defun %fixture-environment (case directory)
  (let* ((home (merge-pathnames #p"home/" directory))
         (extra (%field case "env"))
         (base (list (format nil "HOME=~a" (string-right-trim "/" (namestring home)))
                     (format nil "XDG_CONFIG_HOME=~a" (string-right-trim "/" (namestring (merge-pathnames #p".config/" home))))
                     (format nil "XDG_DATA_HOME=~a" (string-right-trim "/" (namestring (merge-pathnames #p".data/" home))))
                     (format nil "XDG_STATE_HOME=~a" (string-right-trim "/" (namestring (merge-pathnames #p".state/" home))))
                     (format nil "XDG_CACHE_HOME=~a" (string-right-trim "/" (namestring (merge-pathnames #p".cache/" home))))
                     (format nil "TMPDIR=~a" (string-right-trim "/" (namestring directory)))
                     (format nil "PATH=~a" (%required-single-bin-path))
                     "NSHELL_AI_COMMAND=/nonexistent"
                     "NO_COLOR=1"
                     "LANG=C.UTF-8"))
         (extra-bindings
           (loop for (name . value) in extra
                 collect (format nil "~a=~a" name value))))
    (append base extra-bindings)))

  (defun %safe-fixture-path (name directory)
    (let ((relative (pathname name)))
      (when (or (uiop:absolute-pathname-p relative)
                (member :up (pathname-directory relative)))
        (error "Fixture path must stay inside its temporary work directory: ~a" name))
      (merge-pathnames relative directory)))

  (defun %write-fixture-files (files directory)
    (dolist (entry files)
      (let ((path (%safe-fixture-path (car entry) directory)))
        (ensure-directories-exist path)
        (with-open-file (stream path
                                :direction :output
                                :if-exists :supersede
                                :external-format :utf-8)
          (write-string (cdr entry) stream)))))

  (defun %run-probe (source case)
  (host-kit:with-temporary-directory (directory)
    (let* ((source-text
             (if (and (consp source)
                      (eq (first source) (find-symbol "FORMAT" "COMMON-LISP")))
                 (apply (symbol-function (first source))
                        (second source)
                        (cddr source))
                 source))
           (home (merge-pathnames #p"home/" directory))
           (script (merge-pathnames #p"case.nsh" directory))
           (environment (%fixture-environment case directory)))
      (ensure-directories-exist home)
      (%write-fixture-files (%field case "files") directory)
      (with-open-file (stream script
                              :direction :output
                              :if-exists :supersede
                              :external-format :utf-8)
        (write-string source-text stream))
      (let ((result
              (host-kit:run-program (%required-nshell-bin)
                                    (list (namestring script))
                                    :directory directory
                                    :input ""
                                    :environment environment
                                    :timeout 20)))
        (list :stdout (host-kit:process-result-stdout result)
              :stderr (host-kit:process-result-stderr result)
              :exit (host-kit:process-result-exit-code result)
              :workdir (namestring directory)
              :real-workdir (namestring (truename directory))
              :home (string-right-trim "/" (namestring home)))))))

  (defun %replace-all (text old new)
    (if (zerop (length old))
        text
        (with-output-to-string (output)
          (loop with start = 0
                for position = (search old text :start2 start)
                while position
                do (write-string text output :start start :end position)
                   (write-string new output)
                   (setf start (+ position (length old)))
                finally (write-string text output :start start)))))

  (defun %normalize-output (text result)
    (let* ((work (string-right-trim "/" (getf result :workdir)))
           (real-work (string-right-trim "/" (getf result :real-workdir)))
           (normalized
             (%normalize-tool-paths
              (%replace-all (%replace-all text work "$WORK") real-work "$WORK"))))
      (if (search "source: $WORK/case.nsh:" normalized)
          (with-input-from-string (input normalized)
            (with-output-to-string (output)
              (loop with in-diagnostic = nil
                    for line = (read-line input nil nil)
                    while line
                    do (let ((trimmed
                               (string-left-trim
                                '(#\Space #\Tab #\Return)
                                line)))
                         (if (eql 0 (search "source: $WORK/case.nsh:" trimmed))
                             (progn
                               (when in-diagnostic (terpri output))
                               (write-string trimmed output)
                               (setf in-diagnostic t))
                             (if in-diagnostic
                                 (progn
                                   (write-char #\Space output)
                                   (write-string trimmed output))
                                 (progn
                                   (write-string line output)
                                   (terpri output))))))))
          normalized)))

  (defun %normalize-nix-tool-path (text tool)
    (let ((suffix (format nil "/bin/~a" tool))
          (prefix "/nix/store/"))
      (with-output-to-string (output)
        (loop with start = 0
              for end = (search suffix text :start2 start)
              while end
              do (let ((store
                         (search prefix text
                                 :start2 start
                                 :end2 end
                                 :from-end t)))
                   (if (and store
                            (> end (+ store (length prefix)))
                            (not (position-if
                                  (lambda (character)
                                    (member character
                                            (list #\Space #\Tab #\Newline
                                                  #\Return #\: #\/)))
                                  text
                                  :start (+ store (length prefix))
                                  :end end)))
                       (progn
                         (write-string text output :start start :end store)
                         (write-string (format nil "<tool>/~a" tool) output)
                         (setf start (+ end (length suffix))))
                       (progn
                         (write-string text output :start start
                                       :end (+ end (length suffix)))
                         (setf start (+ end (length suffix))))))
              finally (write-string text output :start start)))))

  (defun %normalize-tool-paths (text)
    (loop with normalized = text
          for tool in (list "cat" "false" "ls" "printf" "sh" "tr" "wc"
                            "sleep" "sort" "last" "join" "find")
          for replacement = (format nil "<tool>/~a" tool)
          for bare-prefix = (format nil "~a:" tool)
          for normalized-prefix = (format nil "<tool>/~a:" tool)
          do (setf normalized (%normalize-nix-tool-path normalized tool)
                   normalized (%replace-all normalized
                                            (format nil "/usr/bin/~a" tool)
                                            replacement)
                   normalized (%replace-all normalized
                                            (format nil "/bin/~a" tool)
                                            replacement))
             (when (search "No such file or directory" normalized)
               (setf normalized
                     (%replace-all normalized
                                   (format nil "~%~a" bare-prefix)
                                   (format nil "~%~a" normalized-prefix)))
               (when (and (>= (length normalized) (length bare-prefix))
                          (eql 0 (search bare-prefix normalized)))
                 (setf normalized
                       (concatenate 'string normalized-prefix
                                    (subseq normalized
                                            (length bare-prefix))))))
          finally (return normalized)))

  (defun %substring-occurrences (text needle)
    (when (zerop (length needle))
      (error "Cannot count an empty substring"))
    (loop with start = 0
          for position = (search needle text :start2 start)
          while position
          count t
          do (setf start (+ position (length needle)))))

  (defun %assert-l7-expectation (result expectation)
  (let ((exit (getf result :exit))
        (output (%normalize-output (getf result :stdout) result)))
    (let ((expected-exit (getf expectation :exit)))
      (expect exit :to-equal
              (if (eq expected-exit :success) 0 expected-exit)))
    (dolist (value (getf expectation :values))
      (expect (search value output) :to-be-truthy))
    (when (getf expectation :home)
      (expect (search (%normalize-output (getf result :home) result) output)
              :to-be-truthy))
    (when (getf expectation :single-value)
      (expect (%substring-occurrences output (getf expectation :single-value))
              :to-equal 1))))

  (defun %l7-row (id)
    (find id *l7-rows* :key (lambda (row) (getf row :probe-id))
          :test #'string=))

  (defun %assert-fixture-case (case result)
  (let ((expected (%field case "observed_v0_7_0")))
    (expect (getf result :exit) :to-equal (%field expected "exit"))
    (expect (%normalize-output (getf result :stdout) result)
            :to-equal (%normalize-output (%field expected "stdout") result))
    (expect (%normalize-output (getf result :stderr) result)
            :to-equal (%normalize-output (%field expected "stderr") result))))

  (defun %check-fixture-case (id)
  (let* ((case (%fixture-case id))
         (row (%l7-row id))
         (fixture-source (%field case "src"))
         (fixture-result (%run-probe fixture-source case)))
    (if row
        (progn
          (%assert-l7-expectation
           fixture-result
           (or (getf row :fixture-v08) (getf row :v08)))
          (when (getf row :source)
            (%assert-l7-expectation
             (%run-probe (getf row :source) case)
             (getf row :v08))))
        (%assert-fixture-case case fixture-result))))

  (defun %check-l7-next-version (id)
    (let* ((case (%fixture-case id))
           (row (%l7-row id)))
      (unless (getf row :v09)
        (error "L7 row for probe ~a has no next-version expectation" id))
      (%assert-l7-expectation
       (%run-probe (or (getf row :source) (%field case "src")) case)
       (getf row :v09))))

  (defun %probe-ids-at-expansion ()
    (let ((cases (%fixture-cases)))
      (unless (= 151 (length cases))
        (error "Expected 151 language probes, found ~d" (length cases)))
      (mapcar (lambda (case) (%field case "id")) cases)))