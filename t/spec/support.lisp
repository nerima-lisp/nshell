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
    (let* ((path (uiop:getenv "PATH"))
           (expected (uiop:getenv "NSHELL_SPEC_BIN_DIR"))
           (resolved-path
             (and path
                  (uiop:directory-exists-p path)
                  (string-right-trim "/" (namestring (truename path))))))
      (unless (and path expected
                   (string= path expected)
                   resolved-path
                   (not (member resolved-path
                                '("/usr/bin" "/bin" "/usr/local/bin")
                                :test #'string=)))
        (error "t/spec PATH must equal its fixed bin directory"))
      path))
  (defun %check-spec-false-exits-nonzero ()
    (let* ((false-bin
             (merge-pathnames
              #p"false"
              (uiop:ensure-directory-pathname (%required-single-bin-path)))))
      (unless (uiop:file-exists-p false-bin)
        (error "The fixed t/spec bin directory has no false executable"))
      (host-kit:with-temporary-directory (directory)
        (let ((result
                (host-kit:run-program (namestring false-bin) nil
                                      :directory directory
                                      :input ""
                                      :timeout 20)))
          (expect (host-kit:process-result-exit-code result)
                  :to-equal 1)))))

  (defun %fixture-environment (directory)
    (let* ((home (merge-pathnames #p"home/" directory))
           (path (%required-single-bin-path)))
      (list (format nil "HOME=~a" (string-right-trim "/" (namestring home)))
            (format nil "XDG_CONFIG_HOME=~a" (string-right-trim "/" (namestring (merge-pathnames #p".config/" home))))
            (format nil "XDG_DATA_HOME=~a" (string-right-trim "/" (namestring (merge-pathnames #p".data/" home))))
            (format nil "XDG_STATE_HOME=~a" (string-right-trim "/" (namestring (merge-pathnames #p".state/" home))))
            (format nil "XDG_CACHE_HOME=~a" (string-right-trim "/" (namestring (merge-pathnames #p".cache/" home))))
            (format nil "TMPDIR=~a" (string-right-trim "/" (namestring directory)))
            (format nil "PATH=~a" path)
            "NSHELL_AI_COMMAND=/nonexistent"
            "NO_COLOR=1"
            "LANG=C.UTF-8")))

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
             (environment (%fixture-environment directory)))
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
                :source source-text
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
    (if (or (search "source: $WORK/case.nsh:" normalized)
            (search "nshell: crash log:" normalized))
        (let ((final-newline (%output-final-newline-p normalized)))
          (with-input-from-string (input normalized)
            (with-output-to-string (output)
              (let ((in-diagnostic nil)
                    (value-diagnostic nil)
                    (section nil)
                    (pending nil)
                    (pending-prefix ""))
                (labels ((flush-diagnostic-line (newline-p)
                           (when pending
                             (write-string pending-prefix output)
                             (write-string pending output)
                             (when newline-p
                               (terpri output))
                             (setf pending nil
                                   pending-prefix "")))
                         (start-diagnostic (line)
                           (when in-diagnostic
                             (flush-diagnostic-line t))
                           (setf in-diagnostic t
                                 value-diagnostic (search "The value" line)
                                 section (if value-diagnostic :value :ordinary)
                                 pending line
                                 pending-prefix "")))
                  (loop for line = (read-line input nil nil)
                        while line
                        do (let ((trimmed
                                   (string-left-trim
                                    (quote (#\Space #\Tab #\Return)) line)))
                             (cond
                               ((search "nshell: crash log:" trimmed)
                                (when in-diagnostic
                                  (flush-diagnostic-line t))
                                (setf in-diagnostic nil
                                      value-diagnostic nil
                                      section nil)
                                (write-string "nshell: crash log: <CRASH_LOG>" output)
                                (terpri output))
                               ((eql 0 (search "source: $WORK/case.nsh:" trimmed))
                                (start-diagnostic trimmed))
                               ((and in-diagnostic
                                     value-diagnostic
                                     (eql 0 (search "is not of type" trimmed)))
                                (flush-diagnostic-line t)
                                (setf section :marker
                                      pending trimmed
                                      pending-prefix ""))
                               ((and in-diagnostic
                                     value-diagnostic
                                     (eql 0 (search "when binding" trimmed)))
                                (flush-diagnostic-line t)
                                (setf section :binding
                                      pending trimmed
                                      pending-prefix ""))
                               ((and in-diagnostic
                                     (plusp (length line))
                                     (find (char line 0)
                                           (quote (#\Space #\Tab #\Return))))
                                (if (eq section :marker)
                                    (progn
                                      (flush-diagnostic-line t)
                                      (setf section :type
                                            pending trimmed
                                            pending-prefix "  "))
                                    (setf pending (format nil "~a ~a" pending trimmed))))
                               (t
                                (when in-diagnostic
                                  (flush-diagnostic-line t)
                                  (setf in-diagnostic nil
                                        value-diagnostic nil
                                        section nil))
                                (write-string line output)
                                (terpri output)))))
                  (when in-diagnostic
                    (flush-diagnostic-line final-newline)))))))
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
  (labels ((path-character-p (character)
             (or (alphanumericp character)
                 (find character '(#\/ #\. #\_ #\-))))
           (replace-exact-path (input path replacement)
             (with-output-to-string (output)
               (loop with start = 0
                     for position = (search path input :start2 start)
                     while position
                     for end = (+ position (length path))
                     for before-path = (or (zerop position)
                                           (not (path-character-p
                                                 (char input (1- position)))))
                     for after-path = (or (= end (length input))
                                          (not (path-character-p
                                                (char input end))))
                     do (write-string input output :start start :end position)
                        (if (and before-path after-path)
                            (write-string replacement output)
                            (write-string input output :start position :end end))
                        (setf start end)
                     finally (write-string input output :start start)))))
    (loop with normalized = text
          for tool in (list "cat" "false" "ls" "printf" "sh" "tr" "wc"
                            "sleep" "sort" "last" "join" "find")
          for replacement = (format nil "<tool>/~a" tool)
          for bare-prefix = (format nil "~a:" tool)
          for normalized-prefix = (format nil "<tool>/~a:" tool)
          do (setf normalized (%normalize-nix-tool-path normalized tool)
                   normalized
                   (replace-exact-path normalized
                                        (format nil "/usr/bin/~a" tool)
                                        replacement)
                   normalized
                   (replace-exact-path normalized
                                        (format nil "/bin/~a" tool)
                                        replacement)
                   normalized
                   (%replace-all normalized
                                 (format nil "~%~a" bare-prefix)
                                 (format nil "~%~a" normalized-prefix)))
             (when (and (>= (length normalized) (length bare-prefix))
                        (eql 0 (search bare-prefix normalized)))
               (setf normalized
                     (concatenate 'string normalized-prefix
                                  (subseq normalized (length bare-prefix)))))
          finally (return normalized))))

  (progn
  (defun %substring-occurrences (text needle)
    (when (zerop (length needle))
      (error "Cannot count an empty substring"))
    (loop with start = 0
          for position = (search needle text :start2 start)
          while position
          count t
          do (setf start (+ position (length needle)))))

  (defun %output-lines (text)
    (with-input-from-string (input text)
      (loop for line = (read-line input nil nil)
            while line
            collect line)))

  (defun %output-final-newline-p (text)
    (and (plusp (length text))
         (char= (char text (1- (length text))) #\Newline)))

  (defun %without-crash-log-lines (text)
    (let* ((lines (%output-lines text))
           (retained
             (loop for line in lines
                   for index from 0
                   unless (search "nshell: crash log:" line)
                     collect (cons index line)))
           (last-retained (car (last retained)))
           (final-newline
             (and last-retained
                  (or (< (car last-retained) (1- (length lines)))
                      (%output-final-newline-p text)))))
      (with-output-to-string (output)
        (loop for entry in retained
              for first-entry = t then nil
              do (unless first-entry (terpri output))
                 (write-string (cdr entry) output)
              finally
                 (when final-newline (terpri output))))))

  (defun %position-matches-in-stream-p (text position)
  (destructuring-bind (line column source needle) position
    (let* ((location (format nil "case.nsh:~d:~d" line column))
           (lines (%output-lines text))
           (caret-start (1- column))
           (caret-end (+ caret-start (length needle))))
      (and (<= caret-end (length source))
           (string= needle (subseq source caret-start caret-end))
           (= 1 (%substring-occurrences text location))
           (loop for index below (length lines)
                 thereis
                   (and (search location (nth index lines))
                        (let ((source-line (nth (1+ index) lines))
                              (caret-line (nth (+ index 2) lines)))
                          (and source-line
                               caret-line
                               (string= source
                                        (string-left-trim
                                         '(#\Space #\Tab #\Return)
                                         source-line))
                               (= (or (position #\^ caret-line) -1)
                                  caret-start)
                               (<= caret-end (length caret-line))
                               (string= (make-string (length needle)
                                                     :initial-element #\^)
                                        (subseq caret-line caret-start caret-end))))))))))

  (defun %position-matches-p (result position)
    (or (%position-matches-in-stream-p
         (%normalize-output (getf result :stdout) result)
         position)
        (%position-matches-in-stream-p
         (%normalize-output (getf result :stderr) result)
         position)))

  (defun %l7-expectation-matches-p (result expectation
                                  &optional ignore-crash-log)
  (labels ((canonical-output-lines (lines)
             (let ((records nil)
                   (diagnostic nil))
               (dolist (line lines)
                 (cond
                   ((eql 0 (search "source: $WORK/case.nsh:" line))
                    (when diagnostic
                      (push (string-trim '(#\Space #\Tab #\Return)
                                           diagnostic)
                            records))
                    (setf diagnostic
                          (string-trim '(#\Space #\Tab #\Return) line)))
                   ((and diagnostic
                         (plusp (length line))
                         (find (char line 0) '(#\Space #\Tab #\Return)))
                    (setf diagnostic
                          (format nil "~a ~a"
                                  diagnostic
                                  (string-trim '(#\Space #\Tab #\Return)
                                               line))))
                   (t
                    (when diagnostic
                      (push (string-trim '(#\Space #\Tab #\Return)
                                           diagnostic)
                            records)
                      (setf diagnostic nil))
                    (push line records))))
               (when diagnostic
                 (push (string-trim '(#\Space #\Tab #\Return)
                                      diagnostic)
                       records))
               (nreverse records))))
    (let* ((expected-exit (getf expectation :exit))
           (stdout (%normalize-output (getf result :stdout) result))
           (stderr (%normalize-output (getf result :stderr) result))
           (expected-stdout-lines (getf expectation :stdout-lines))
           (expected-stdout-final-newline (getf expectation :final-newline))
           (actual-stderr
             (if ignore-crash-log
                 (%without-crash-log-lines stderr)
                 stderr))
           (expected-stderr-lines (getf expectation :stderr-lines))
           (expected-single-value (getf expectation :single-value))
           (expected-line-count (getf expectation :stdout-line-count))
           (position (getf expectation :position)))
      (and (eql (getf result :exit)
                (if (eq expected-exit :success) 0 expected-exit))
           (or (not (or (member :stdout-lines expectation)
                        (getf expectation :home)))
               (if (getf expectation :diagnostic-output)
                   (equal (canonical-output-lines (%output-lines stdout))
                          (canonical-output-lines expected-stdout-lines))
                   (equal (%output-lines stdout) expected-stdout-lines)))
           (or (not (or (member :final-newline expectation)
                        (getf expectation :home)))
               (eql (%output-final-newline-p stdout)
                    expected-stdout-final-newline))
           (or (null expected-line-count)
               (= (length (%output-lines stdout)) expected-line-count))
           (if (member :stderr-lines expectation)
               (and (equal (%output-lines actual-stderr)
                           expected-stderr-lines)
                    (eql (%output-final-newline-p actual-stderr)
                         (getf expectation :stderr-final-newline)))
               (equal actual-stderr ""))
           (or (null expected-single-value)
               (= 1 (%substring-occurrences
                     (format nil "~a~%~a" stdout actual-stderr)
                     expected-single-value)))
           (or (null position)
               (%position-matches-p result position))))))

  (defun %fixture-expectation (case result)
  (let* ((observed (%field case "observed_v0_7_0"))
         (stdout (%normalize-output (%field observed "stdout") result))
         (stderr (%normalize-output (%field observed "stderr") result)))
    (list :exit (%field observed "exit")
          :stdout-lines (%output-lines stdout)
          :final-newline (%output-final-newline-p stdout)
          :diagnostic-output t
          :stderr-lines (%output-lines stderr)
          :stderr-final-newline (%output-final-newline-p stderr))))

  (defun %fixture-result-matches-p (case result
                                   &optional ignore-crash-log)
  (%l7-expectation-matches-p
   result
   (%fixture-expectation case result)
   ignore-crash-log))

  (defun %rewrite-cue-present-p (text)
  (let ((markers '("Suggested rewrite:"
                   "Rewrite:"
                   "Fix:"
                   "Example:"
                   "書き換え案:"
                   "書き換え案"
                   "書き換え例:"
                   "書き換え:"
                   "提案:"
                   "例:")))
    (loop for marker in markers
          thereis
            (let ((position (search marker text)))
              (and position
                   (let* ((payload-start (+ position (length marker)))
                          (line-end (or (position #\Newline text
                                                  :start payload-start)
                                        (length text)))
                          (payload (string-trim '(#\Space #\Tab #\Return #\:)
                                                (subseq text payload-start line-end))))
                     (or (plusp (length payload))
                         (let* ((next-start (min (length text)
                                                 (1+ line-end)))
                                (next-end (or (position #\Newline text
                                                        :start next-start)
                                              (length text))))
                           (plusp
                            (length
                             (string-trim '(#\Space #\Tab #\Return)
                                          (subseq text next-start next-end))))))))))))

  (defun %warning-expectation-matches-p (result warning)
  (let* ((stdout (%normalize-output (getf result :stdout) result))
         (stderr (%normalize-output (getf result :stderr) result))
         (combined (format nil "~a~%~a" stdout stderr))
         (code (getf warning :code))
         (code-count (%substring-occurrences combined code))
         (message-match
           (or (and (getf warning :message-en)
                    (search (getf warning :message-en) combined))
               (and (getf warning :message-ja)
                    (search (getf warning :message-ja) combined))))
         (rewrite (getf warning :rewrite)))
    (and (= code-count 1)
         message-match
         (or (null rewrite) (search rewrite combined))
         (%rewrite-cue-present-p combined))))
)

  (defun %assert-l7-expectation (result expectation)
  (let* ((expected-exit (getf expectation :exit))
         (stdout (%normalize-output (getf result :stdout) result))
         (stderr (%normalize-output (getf result :stderr) result))
         (expected-stdout-lines
           (if (member :stdout-lines expectation)
               (getf expectation :stdout-lines)
               (if (getf expectation :home)
                   (list (%normalize-output (getf result :home) result))
                   nil)))
         (expected-stdout-final-newline
           (if (member :final-newline expectation)
               (getf expectation :final-newline)
               (not (null (getf expectation :home)))))
         (single-value (getf expectation :single-value))
         (line-count (getf expectation :stdout-line-count))
         (position (getf expectation :position)))
    (expect (getf result :exit) :to-equal
            (if (eq expected-exit :success) 0 expected-exit))
    (when (or (member :stdout-lines expectation)
              (getf expectation :home))
      (expect (%output-lines stdout) :to-equal expected-stdout-lines))
    (when (or (member :final-newline expectation)
              (getf expectation :home))
      (expect (%output-final-newline-p stdout) :to-equal
              expected-stdout-final-newline))
    (if (member :stderr-lines expectation)
        (progn
          (expect (%output-lines stderr) :to-equal
                  (getf expectation :stderr-lines))
          (expect (%output-final-newline-p stderr) :to-equal
                  (getf expectation :stderr-final-newline)))
        (expect stderr :to-equal ""))
    (when line-count
      (expect (length (%output-lines stdout)) :to-equal line-count))
    (when single-value
      (expect (%substring-occurrences (format nil "~a~%~a" stdout stderr)
                                     single-value)
              :to-equal 1))
    (when position
      (expect (%position-matches-p result position) :to-be-truthy))))

  (defun %l7-row (id)
  (or (find id *l7-rows* :key (lambda (row) (getf row :probe-id))
            :test #'string=)
      (loop for row in *l7-rows*
            for related = (find id
                                (append (getf row :additional-probes)
                                        (getf row :additional-crash-probes))
                                :key (lambda (probe) (getf probe :probe-id))
                                :test #'string=)
            when related
              return related)))

  (defun %check-fixture-baseline (id)
  (let* ((case (%fixture-case id))
         (result (%run-probe (%field case "src") case)))
    (expect (%fixture-result-matches-p case result t)
            :to-be-truthy)))

  (defun %check-l7-v08 (id)
  (let* ((row (%l7-row id))
         (case (%fixture-case id))
         (baseline (%run-probe (%field case "src") case))
         (expectation (getf row :v08)))
    (unless (and expectation (not (eq expectation :observed)))
      (error "L7 row for probe ~a has no v0.8 expectation" id))
    (unless (%fixture-result-matches-p case baseline t)
      (return-from %check-l7-v08 nil))
    (%assert-l7-expectation
     (%run-probe (or (getf row :source) (%field case "src")) case)
     expectation)))

  (defun %check-l7-next-version (id &optional (kind :next-version))
  (let* ((case (%fixture-case id))
         (row (%l7-row id))
         (fixture-source (%field case "src")))
    (case kind
      (:next-version
       (unless (and row (getf row :v09))
         (error "L7 row for probe ~a has no next-version expectation" id))
       (let ((baseline (%run-probe fixture-source case)))
         (unless (%fixture-result-matches-p case baseline t)
           (return-from %check-l7-next-version nil)))
       (let* ((next-source
                (if (eq (getf row :v09-source) :fixture)
                    fixture-source
                    (or (getf row :v09-source)
                        (getf row :source)
                        fixture-source)))
              (result (%run-probe next-source case)))
         (%assert-l7-expectation result (getf row :v09))))
      (:warning
       (unless (and row (getf row :warning))
         (error "L7 row for probe ~a has no warning expectation" id))
       (let ((baseline (%run-probe fixture-source case)))
         (unless (%fixture-result-matches-p case baseline)
           (return-from %check-l7-next-version nil)))
       (let* ((warning-source (or (getf row :warning-source) fixture-source))
              (result (%run-probe warning-source case)))
         (unless (%fixture-result-matches-p case result)
           (return-from %check-l7-next-version nil))
         (expect (%warning-expectation-matches-p
                  result (getf row :warning))
                 :to-be-truthy)))
      (:crash-baseline
       (unless (and row (getf row :crash-baseline))
         (error "L7 row for probe ~a has no crash baseline" id))
       (let* ((crash-source (or (getf row :crash-source) fixture-source))
              (result (%run-probe crash-source case)))
         (expect (%l7-expectation-matches-p
                  result (getf row :crash-baseline) t)
                 :to-be-truthy)))
      (:crash
       (let* ((crash-source (or (getf row :crash-source) fixture-source))
              (result (%run-probe crash-source case))
              (baseline-matches
                (if (and row (getf row :crash-baseline))
                    (%l7-expectation-matches-p
                     result (getf row :crash-baseline) t)
                    (%fixture-result-matches-p case result t))))
         (unless baseline-matches
           (return-from %check-l7-next-version nil))
         (expect (%substring-occurrences
                  (%normalize-output (getf result :stderr) result)
                  "nshell: crash log:")
                 :to-equal 0)))
      (otherwise
       (error "Unknown L7 expectation kind ~a" kind)))))

  (defun %probe-ids-at-expansion ()
    (let ((cases (%fixture-cases)))
      (unless (= 151 (length cases))
        (error "Expected 151 language probes, found ~d" (length cases)))
      (mapcar (lambda (case) (%field case "id")) cases)))