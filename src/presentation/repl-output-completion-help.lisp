;;; Completion help lookup and completion-session warming.
(in-package #:nshell.presentation)

(defparameter *completion-help-timeout* 3
  "Maximum seconds to wait for a dynamic completion help lookup.")

(defparameter *completion-help-max-output-chars* (* 128 1024)
  "Maximum help output size accepted by the completion parser.")

(progn
  (defun %completion-help-command-parts (command)
    (when (and (stringp command)
               (plusp (length command))
               (not (find-if
                     (lambda (character)
                       (member character
                               '(#\; #\| #\& #\< #\> #\` #\$ #\( #\)
                                 #\' #\" #\\ #\Newline #\Return)))
                     command)))
      (let ((parts nil)
            (start nil)
            (length (length command)))
        (labels ((flush (end)
                   (when start
                     (push (subseq command start end) parts)
                     (setf start nil))))
          (loop for index from 0 below length
                for character = (char command index)
                do (if (find character '(#\Space #\Tab))
                       (flush index)
                       (unless start
                         (setf start index))))
          (flush length))
        (nreverse parts))))

  (defun %fetch-completion-help (command resolved-path)
    (let ((parts (%completion-help-command-parts command)))
      (when parts
        (let ((nshell.infrastructure.acl:*external-command-timeout*
                *completion-help-timeout*))
          (nshell.infrastructure.acl:run-external-capture
           resolved-path
           (append (rest parts) '("--help"))
           :max-output-chars *completion-help-max-output-chars*)))))

  (defparameter *completion-help-fetcher* #'%fetch-completion-help
    "Function of COMMAND and RESOLVED-PATH used to fetch dynamic completion help.")

  (defun %completion-help-command-info (command)
    (multiple-value-bind (kind path)
        (nshell.application:resolve-command-path
         (%make-repl-shell-context) command)
      (when (and (eq kind :path) path)
        (handler-case
            (let* ((resolved-path (namestring (truename path)))
                   (mtime (file-write-date resolved-path)))
              (list resolved-path mtime))
          (file-error () nil)))))

  (defparameter *completion-help-command-info-function*
    #'%completion-help-command-info
    "Resolve an allowlisted command to its canonical executable path and mtime.")

  (defparameter *completion-help-cache-directory-override* nil
    "Test override for the dynamic completion help cache directory.")

  (defstruct (completion-help-result-channel
              (:constructor %make-completion-help-result-channel))
    (mutex (sb-thread:make-mutex :name "nshell completion help results"))
    (results nil))

  (defparameter *completion-help-result-channel*
    (%make-completion-help-result-channel))

  (defparameter *completion-help-catalog-command-cache*
    (let ((cache (make-hash-table :test #'equal)))
      (dolist (spec (nshell.domain.completion:external-completion-command-specs)
               cache)
        (when (and (stringp (first spec))
                   (not (find #\/ (first spec))))
          (setf (gethash (first spec) cache) t))))
    "Set of catalogued external commands that may be enriched from help output.")

  (defun %completion-help-default-command-names ()
    (let ((names nil))
      (maphash (lambda (name present)
                 (declare (ignore present))
                 (push name names))
               *completion-help-catalog-command-cache*)
      (sort names #'string<)))

  (defun %completion-help-simple-command-name-p (name)
    (and (stringp name)
         (<= (length name) 128)
         (plusp (length name))
         (every (lambda (character)
                  (or (and (char<= #\a character) (char<= character #\z))
                      (and (char<= #\A character) (char<= character #\Z))
                      (digit-char-p character)
                      (find character '(#\- #\_ #\. #\+))))
                name)))

  (defun %completion-help-environment-command-names (value)
    (loop with start = 0
          for end = (position #\: value :start start)
          for raw-name = (subseq value start end)
          for name = (string-trim '(#\Space #\Tab) raw-name)
          when (%completion-help-simple-command-name-p name)
            collect name
          until (null end)
          do (setf start (1+ end))))

  (defun %completion-help-allowed-command-p (command)
    (let ((setting
           (nshell.domain.environment:env-get
            (ensure-environment) "NSHELL_COMPLETION_HELP_ALLOWLIST")))
      (cond
       ((null setting)
        (%completion-help-catalogued-command-p command))
       ((zerop (length setting))
        nil)
       (t
        (member command
                (%completion-help-environment-command-names setting)
                :test (function string=))))))

  (defun %completion-help-catalogued-command-p (command)
    (gethash command *completion-help-catalog-command-cache*))

  (defun %completion-help-text-p (output)
    (and (stringp output)
         (plusp (length output))
         (or (search "usage" output :test #'char-equal)
             (search "options" output :test #'char-equal)
             (search "commands" output :test #'char-equal)
             (search "flags" output :test #'char-equal))))

  (defun %completion-help-eligible-command-p (command)
    (let ((parts (%completion-help-command-parts command)))
      (and parts
           (%completion-help-simple-command-name-p (first parts))
           (%completion-help-allowed-command-p (first parts)))))

  (defun %completion-help-output-valid-p (output exit-code &optional truncated-p)
    (and (not truncated-p)
         (eql exit-code 0)
         (stringp output)
         (<= (length output) *completion-help-max-output-chars*)
         (%completion-help-text-p output)))

  (defun %completion-help-cache-help-text (command output exit-code
                                               &optional truncated-p)
    (if (%completion-help-output-valid-p output exit-code truncated-p)
        (progn
          (nshell.domain.completion:kb-add-command-from-help
           *kb* command output)
          :loaded)
        :missing))

  (defun %completion-help-xdg-cache-home ()
    (let ((value
            (nshell.infrastructure.acl:current-environment-value
             "XDG_CACHE_HOME")))
      (when (and value (plusp (length value)))
        (let ((path (pathname value)))
          (when (eq :absolute (first (pathname-directory path)))
            path)))))

  (defun %completion-help-cache-directory ()
    (or *completion-help-cache-directory-override*
        (let ((xdg (%completion-help-xdg-cache-home)))
          (if xdg
              (merge-pathnames
               #P"nshell/completion-help/"
               (uiop:ensure-directory-pathname xdg))
              (merge-pathnames
               #P".cache/nshell/completion-help/"
               (user-homedir-pathname))))))
 (defun %completion-help-cache-key (command)
    (let ((hash #xcbf29ce484222325))
      (loop for character across command
            do (setf hash
                     (logand #xffffffffffffffff
                             (* (logxor hash (char-code character))
                                #x100000001b3))))
      (format nil "~16,'0X" hash)))
 (defun %completion-help-cache-file (command directory)
    (merge-pathnames
     (make-pathname :name (%completion-help-cache-key command)
                    :type "cache")
     (uiop:ensure-directory-pathname directory)))
 (defun %completion-help-encode-cache-field (value)
    (with-output-to-string (stream)
      (loop for character across value
            do (format stream "~6,'0X" (char-code character)))))
 (defun %completion-help-decode-cache-field (value)
    (when (zerop (mod (length value) 6))
      (let ((characters nil))
        (loop for start from 0 below (length value) by 6
              for code = (parse-integer value
                                        :start start :end (+ start 6)
                                        :radix 16 :junk-allowed nil)
              for character = (code-char code)
              unless character
                do (return-from %completion-help-decode-cache-field nil)
              do (push character characters))
        (coerce (nreverse characters) 'string))))
 (defun %completion-help-cache-integer (line)
    (when (and line
               (plusp (length line))
               (every #'digit-char-p line))
      (parse-integer line :junk-allowed nil)))

  (defun %completion-help-open-cache-stream (cache-file maximum-bytes)
    (let ((fd
           (handler-case
               (sb-posix:open
                (namestring cache-file)
                (logior sb-posix:o-rdonly
                        sb-posix:o-nofollow
                        sb-posix:o-nonblock))
             (sb-posix:syscall-error (condition)
                                     (if (member (sb-posix:syscall-errno condition)
                                                 (list sb-posix:enoent sb-posix:enotdir sb-posix:eloop))
                                         nil
                                       (error condition))))))
      (when fd
        (unwind-protect
            (let ((stat (sb-posix:fstat fd)))
              (when (and (sb-posix:s-isreg (sb-posix:stat-mode stat))
                         (<= 0 (sb-posix:stat-size stat) maximum-bytes))
                (prog1
                    (sb-sys:make-fd-stream
                     fd :input t
                     :element-type (quote character)
                     :external-format
                     (quote (:utf-8 :replacement #\Replacement_Character))
                     :auto-close t
                     :pathname cache-file)
                  (setf fd nil))))
          (when fd
            (sb-posix:close fd))))))
 (defun %completion-help-read-bounded-cache-line (stream maximum-length)
      (let ((line (make-string-output-stream))
            (length 0))
        (loop for character = (read-char stream nil :eof)
              do (cond
                  ((eq character :eof)
                   (return nil))
                  ((char= character #\Newline)
                   (return (get-output-stream-string line)))
                  ((>= length maximum-length)
                   (return nil))
                  (t
                   (incf length)
                   (write-char character line))))))
 (defun %completion-help-read-cache (command resolved-path mtime directory)
      (let* ((cache-file (%completion-help-cache-file command directory))
             (maximum-bytes
              (+ 256
                 (* 6 (+ (length command) (length resolved-path)))
                 (* 4 *completion-help-max-output-chars*)))
             (stream (%completion-help-open-cache-stream cache-file maximum-bytes)))
        (when stream
          (unwind-protect
              (handler-case
                  (let* ((version (%completion-help-read-bounded-cache-line stream 64))
                         (cached-command
                          (%completion-help-decode-cache-field
                           (%completion-help-read-bounded-cache-line
                            stream (* 6 (length command)))))
                         (cached-path
                          (%completion-help-decode-cache-field
                           (%completion-help-read-bounded-cache-line
                            stream (* 6 (length resolved-path)))))
                         (cached-mtime
                          (%completion-help-cache-integer
                           (%completion-help-read-bounded-cache-line stream 32)))
                         (output-length
                          (%completion-help-cache-integer
                           (%completion-help-read-bounded-cache-line stream 32))))
                    (when (and (equal version "NSHELL-COMPLETION-HELP-1")
                               (equal command cached-command)
                               (equal resolved-path cached-path)
                               (eql mtime cached-mtime)
                               output-length
                               (plusp output-length)
                               (<= output-length
                                   *completion-help-max-output-chars*))
                      (let ((output (make-string output-length)))
                        (when (and (= output-length
                                      (read-sequence output stream))
                                   (eql #\Newline (read-char stream nil nil))
                                   (eq :eof (read-char stream nil :eof))
                                   (not (find #\Replacement_Character output))
                                   (%completion-help-text-p output))
                          output))))
                (parse-error () nil))
            (close stream)))))

  (defun %completion-help-write-cache
      (command resolved-path mtime output directory)
    (let ((cache-file (%completion-help-cache-file command directory)))
      (ensure-directories-exist cache-file)
      (loop repeat 32
            for temporary-file =
              (pathname
               (format nil "~a.~d.~36r.tmp"
                       (namestring cache-file) (sb-posix:getpid)
                       (random most-positive-fixnum)))
            do (let ((fd
                       (handler-case
                           (sb-posix:open
                            (namestring temporary-file)
                            (logior sb-posix:o-wronly sb-posix:o-creat
                                    sb-posix:o-excl sb-posix:o-nofollow
                                    sb-posix:o-nonblock)
                            #o600)
                         (sb-posix:syscall-error (condition)
                           (unless (= (sb-posix:syscall-errno condition)
                                      sb-posix:eexist)
                             (error condition))))))
                 (when fd
                   (let ((published-p nil)
                         (fd-open-p t))
                     (unwind-protect
                          (progn
                            (let ((stream
                                    (sb-sys:make-fd-stream
                                     fd :output t :element-type 'character
                                     :external-format :utf-8 :auto-close t
                                     :pathname temporary-file)))
                              (setf fd-open-p nil)
                              (unwind-protect
                                   (progn
                                     (write-line "NSHELL-COMPLETION-HELP-1" stream)
                                     (write-line
                                      (%completion-help-encode-cache-field command)
                                      stream)
                                     (write-line
                                      (%completion-help-encode-cache-field
                                       resolved-path)
                                      stream)
                                     (write-line (princ-to-string mtime) stream)
                                     (write-line (princ-to-string (length output))
                                                 stream)
                                     (write-string output stream)
                                     (terpri stream)
                                     (finish-output stream)
                                     (sb-posix:fsync fd))
                                (close stream)))
                            (sb-posix:rename (namestring temporary-file)
                                             (namestring cache-file))
                            (setf published-p t))
                       (when fd-open-p
                         (sb-posix:close fd))
                       (unless published-p
                         (handler-case
                             (sb-posix:unlink (namestring temporary-file))
                           (sb-posix:syscall-error (condition)
                             (unless (= (sb-posix:syscall-errno condition)
                                        sb-posix:enoent)
                               (error condition)))))
                     (return-from %completion-help-write-cache published-p))))) finally (error "Unable to allocate a temporary completion-help cache file."))))

  (defun %completion-help-fetch-cache-result
      (command resolved-path mtime directory fetcher)
    (let ((cached
            (%completion-help-read-cache
             command resolved-path mtime directory)))
      (if cached
          (values :loaded cached)
          (multiple-value-bind (output exit-code truncated-p)
              (handler-case
                  (funcall fetcher command resolved-path)
                (error () (values nil nil nil)))
            (if (%completion-help-output-valid-p
                 output exit-code truncated-p)
                (progn
                  (%completion-help-write-cache
                   command resolved-path mtime output directory)
                  (values :loaded output))
                (values :missing nil))))))

  (defun %completion-help-publish-result (channel result)
    (sb-thread:with-mutex
        ((completion-help-result-channel-mutex channel))
      (push result (completion-help-result-channel-results channel))))

  (defun %completion-help-run-worker
      (channel command resolved-path mtime request-id directory fetcher)
    (let ((nshell.infrastructure.acl::*foreground-pgid* 0))
      (handler-case
          (multiple-value-bind (status output)
              (%completion-help-fetch-cache-result
               command resolved-path mtime directory fetcher)
            (%completion-help-publish-result
             channel
             (list :command command
                   :path resolved-path
                   :mtime mtime
                   :request-id request-id
                   :status status
                   :output output)))
        (error (condition)
          (%completion-help-publish-result
           channel
           (list :command command
                 :path resolved-path
                 :mtime mtime
                 :request-id request-id
                 :status :error
                 :condition condition))))))

  (defun %completion-help-drain-results ()
    (let ((channel *completion-help-result-channel*))
      (sb-thread:with-mutex
          ((completion-help-result-channel-mutex channel))
        (prog1 (nreverse
                (completion-help-result-channel-results channel))
          (setf (completion-help-result-channel-results channel) nil)))))

  (defun %completion-help-command-baseline (command)
    (let* ((kb *kb*)
           (facts
             (remove-if-not
              (lambda (fact)
                (and (member
                      (nshell.domain.completion::fact-predicate fact)
                      '(nshell.domain.completion::command-registered
                        nshell.domain.completion::subcommand-of
                        nshell.domain.completion::has-flag
                        nshell.domain.completion::option-value
                        nshell.domain.completion::option-value-kind
                        nshell.domain.completion::exclusive-group
                        nshell.domain.completion::describes
                        nshell.domain.completion::flag-describes))
                     (equal command
                            (first
                             (nshell.domain.completion::fact-args fact)))))
              (nshell.domain.completion::rule-knowledge-base-facts kb)))
           (command-description
             (gethash
              command
              (nshell.domain.completion::knowledge-base-command-description-facts
               kb)))
           (flag-descriptions
             (let ((table
                     (gethash
                      command
                      (nshell.domain.completion::knowledge-base-flag-description-facts
                       kb))))
               (when table
                 (let ((entries nil))
                   (maphash (lambda (flag fact)
                              (push (cons flag fact) entries))
                            table)
                   entries)))))
      (list :facts facts
            :command-description command-description
            :flag-descriptions flag-descriptions)))

  (defun %completion-help-restore-command-baseline (command baseline)
    (nshell.domain.completion:kb-remove-command *kb* command)
    (dolist (fact (getf baseline :facts))
      (nshell.domain.completion:assert-fact! *kb* fact))
    (let ((command-description (getf baseline :command-description)))
      (when command-description
        (setf (gethash
               command
               (nshell.domain.completion::knowledge-base-command-description-facts
                *kb*))
              command-description)))
    (when (getf baseline :flag-descriptions)
      (let ((table
              (or (gethash
                   command
                   (nshell.domain.completion::knowledge-base-flag-description-facts
                    *kb*))
                  (setf (gethash
                         command
                         (nshell.domain.completion::knowledge-base-flag-description-facts
                          *kb*))
                        (make-hash-table :test #'equal)))))
        (dolist (entry (getf baseline :flag-descriptions))
          (setf (gethash (car entry) table) (cdr entry)))))
    nil)

  (defun %completion-help-state-matches-p (state path mtime)
    (and state
         (equal path (getf state :path))
         (eql mtime (getf state :mtime))))

  (defun %completion-help-start-worker
      (command path mtime request-id)
    (let ((channel *completion-help-result-channel*)
          (directory (%completion-help-cache-directory))
          (fetcher *completion-help-fetcher*))
      (sb-thread:make-thread
       (lambda ()
         (%completion-help-run-worker
          channel command path mtime request-id directory fetcher))
       :name (format nil "nshell completion help ~a" command))))

  (defun %completion-help-mark-result (result)
    (let* ((command (getf result :command))
           (state (gethash command *completion-help-cache*)))
      (when (and state
                 (eq :loading (getf state :status))
                 (equal (getf result :path) (getf state :path))
                 (eql (getf result :mtime) (getf state :mtime))
                 (eq (getf result :request-id) (getf state :request-id)))
        (let* ((status (getf result :status))
               (baseline (getf state :baseline)))
          (when (eq status :loaded)
            (setf status
                  (%completion-help-cache-help-text
                   command (getf result :output) 0)))
          (when (eq status :error)
            (format *error-output*
                    "nshell: completion help cache failed for ~a: ~a~%"
                    command (getf result :condition)))
          (setf (gethash command *completion-help-cache*)
                (list :status status
                      :path (getf state :path)
                      :mtime (getf state :mtime)
                      :request-id (getf state :request-id)
                      :baseline baseline))))))

  (defun %apply-completion-help-results ()
    (dolist (result (%completion-help-drain-results))
      (%completion-help-mark-result result))
    nil)

  (defun %completion-help-mark-state
      (command status path mtime request-id baseline)
    (setf (gethash command *completion-help-cache*)
          (list :status status
                :path path
                :mtime mtime
                :request-id request-id
                :baseline baseline)))

  (defun %warm-command-completion-help (command)
    (when (%completion-help-eligible-command-p command)
      (let* ((command-name (first (%completion-help-command-parts command)))
             (state (gethash command *completion-help-cache*))
             (info
               (funcall *completion-help-command-info-function* command-name))
             (path (first info))
             (mtime (second info)))
        (unless (%completion-help-state-matches-p state path mtime)
          (let ((baseline
                  (or (getf state :baseline)
                      (%completion-help-command-baseline command))))
            (when state
              (%completion-help-restore-command-baseline command baseline))
            (let ((request-id (gensym "COMPLETION-HELP-")))
              (if (and path (integerp mtime))
                  (progn
                    (%completion-help-mark-state
                     command :loading path mtime request-id baseline)
                    (handler-case
                        (%completion-help-start-worker
                         command path mtime request-id)
                      (error (condition)
                        (format *error-output*
                                "nshell: unable to start completion help for ~a: ~a~%"
                                command condition)
                        (%completion-help-mark-state
                         command :missing path mtime request-id baseline))))
                  (%completion-help-mark-state
                   command :missing path mtime request-id baseline))))))))

  (defun %warm-command-completion-help-path
      (knowledge-base command argument-words prefix)
    (when (%completion-help-simple-command-name-p command)
      (let ((resolved command)
            (safe-argument-words
              (loop for word in argument-words
                    while (%completion-help-simple-command-name-p word)
                    collect word)))
        (loop
          (%warm-command-completion-help resolved)
          (let ((next
                  (nshell.domain.completion:kb-resolve-command-path
                   knowledge-base command safe-argument-words prefix)))
            (if (string= next resolved)
                (return)
                (setf resolved next))))))))

(defun %completion-session-valid-p (state)
  (with-normalized-input-state (state state)
    (let ((candidates (input-state-last-candidates state))
          (selected-index (input-state-completion-index state)))
      (and candidates
           (>= selected-index 0)
           (< selected-index (length candidates))
           (let ((base-buffer (input-state-completion-base-buffer state))
                 (base-cursor (input-state-completion-base-cursor state)))
             (and base-buffer
                  base-cursor
                  (multiple-value-bind (expected-buffer expected-cursor)
                      (apply-completion base-buffer
                                        (nth selected-index candidates)
                                        :cursor base-cursor)
                    (and (string= expected-buffer
                                  (input-state-buffer state))
                         (= expected-cursor
                            (input-state-cursor-pos state))))))))))
(defun %repl-completion-fallback-head-classification (context head-source)
  (let* ((upper-name (string-upcase head-source))
         (package-separator (position #\: upper-name))
         (package-name (and package-separator
                            (subseq upper-name 0 package-separator)))
         (symbol-name (if package-separator
                          (subseq upper-name (1+ package-separator))
                          upper-name))
         (user-package (find-package "NSHELL.USER"))
         (user-symbol (and user-package
                           (find-symbol head-source user-package)))
         (common-lisp-symbol (find-symbol symbol-name "COMMON-LISP"))
         (function-table
           (nshell.application:shell-context-function-table context)))
    (cond
      (package-name :host-form)
      ((nth-value 1 (gethash head-source function-table))
       :command-island)
      ((or (and common-lisp-symbol
                (or (special-operator-p common-lisp-symbol)
                    (macro-function common-lisp-symbol)
                    (fboundp common-lisp-symbol)))
           (and user-symbol (fboundp user-symbol)))
       :host-form)
      (t :command-island))))
(defun %repl-completion-head-classifier (context)
  (lambda (head-source)
    (handler-case
        (nshell.application:classify-sexp-head context head-source)
      (nshell.application:wp-interface-not-implemented (condition)
        (if (and (string= "L02"
                         (nshell.application:wp-interface-not-implemented-owner-wp
                          condition))
                 (eq 'nshell.application:classify-sexp-head
                     (nshell.application:wp-interface-not-implemented-interface
                      condition)))
            (%repl-completion-fallback-head-classification context head-source)
            (error condition))))))

(defun %refresh-completion-session-state (state)
  (with-normalized-input-state (state state)
    (%apply-completion-help-results)
    (let* ((text (input-state-buffer state))
           (cursor (input-state-cursor-pos state))
           (shell-context (%make-repl-shell-context))
           (scan-result
             (nshell.domain.parsing:scan-input
              text
              :cursor cursor
              :reader-context :auto
              :head-classifier
              (%repl-completion-head-classifier shell-context)))
           (role
             (nshell.domain.parsing:scan-result-cursor-role scan-result))
           (context
             (nshell.domain.completion:completion-context-for-scan
              scan-result cursor))
           (command
             (nshell.domain.completion:completion-context-command context))
           (command-position-p
             (nshell.domain.completion:completion-context-command-position-p
              context))
           (completion-role-p
             (member role '(:command-head :argument :redirect-target)
                     :test #'eq))
           (completion-path
             (nshell.domain.environment:env-get (ensure-environment) "PATH"))
           (filesystem
             (nshell.infrastructure.acl:make-host-filesystem)))
      (when (and (not command-position-p) (plusp (length command)))
        (%warm-command-completion-help-path
         *kb*
         command
         (nshell.domain.completion:completion-context-argument-words context)
         (nshell.domain.completion:completion-context-argument-prefix context)))
      (let ((candidates
              (when (and completion-role-p (plusp (length text)))
                (apply #'nshell.domain.completion:complete-in-context
                       *kb* text context
                       :path completion-path
                       :filesystem filesystem
                       :alias-table *aliases*
                       :function-table *functions*
                       (repl-completion-environment-arguments)))))
        (if candidates
            (multiple-value-bind (extended-state extended-p)
                (maybe-extend-completion-common-prefix state candidates)
              (declare (ignore extended-p))
              (setf (input-state-last-candidates extended-state) candidates)
              (values extended-state candidates))
            (values (clear-completion-session-state state) nil))))))
