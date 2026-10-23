(require :asdf)
(require :sb-posix)
(progn
  (require :sb-posix)
  (eval-when (:compile-toplevel :load-toplevel :execute)
    (defpackage #:nshell.infrastructure.acl
      (:use #:cl)
      (:export #:current-environment-value)))
  (setf (symbol-function
         (intern "CURRENT-ENVIRONMENT-VALUE"
                 "NSHELL.INFRASTRUCTURE.ACL"))
        (lambda (name) (sb-ext:posix-getenv name))))
(load (merge-pathnames "asdf-runtime.lisp" *load-truename*))
(nshell-configure-writable-asdf-output)
(asdf:load-system "cl-history-kit")
(defpackage #:nshell.infrastructure.persistence (:use #:cl) (:export #:load-history-file #:history-record-text))
(load (merge-pathnames "../src/infrastructure/persistence/file-history.lisp"
                       *load-truename*))

(let ((arguments (uiop:command-line-arguments)))
  (when (equal "--history-child-append" (first arguments))
    (write-line "HISTORY-CHILD-READY")
    (finish-output)
    (let ((text (read-line *standard-input* nil nil)))
      (unless text
        (uiop:quit 2))
      (write-line "HISTORY-CHILD-APPENDING")
      (finish-output)
      (let ((nshell.infrastructure.persistence::*history-file-path-override*
              (pathname (second arguments)))
            (*error-output* (make-string-output-stream)))
        (nshell.infrastructure.persistence::append-history-entry text)
        (let ((errors (get-output-stream-string *error-output*)))
          (write-string errors)
          (uiop:quit (if (zerop (length errors)) 0 4)))))))


(defun check-history-reader-lock (path check)
  (let* ((script (namestring *load-truename*))
         (lock-path (nshell.infrastructure.persistence::%history-lock-path path))
         (texts '("shared command" "shared command" "distinct command"))
         (children nil)
         (lock-fd nil))
    (let ((nshell.infrastructure.persistence::*history-file-path-override* path))
      (when (probe-file path)
        (delete-file path))
      (nshell.infrastructure.persistence::append-history-entry "seed"))
    (setf lock-fd (nshell.infrastructure.persistence::%open-history-lock path))
    (unwind-protect
         (progn
           (loop repeat (length texts)
                 do (let ((child
                            (uiop:launch-program
                             (list (namestring sb-ext:*runtime-pathname*)
                                   "--script" script
                                   "--history-child-append"
                                   (namestring path))
                             :input :stream :output :stream
                             :error-output :output)))
                      (push child children)
                      (unless (sb-ext:with-timeout 30
                                (loop for line =
                                        (read-line
                                         (uiop:process-info-output child)
                                         nil nil)
                                      while line
                                      thereis
                                        (string= "HISTORY-CHILD-READY" line)))
                        (error "History child did not become ready."))))
           (setf children (nreverse children))
           (loop for child in children
                 for text in texts
                 do (let ((input (uiop:process-info-input child)))
                      (write-line text input)
                      (finish-output input)
                      (close input)
                      (unless (string= "HISTORY-CHILD-APPENDING"
                                       (sb-ext:with-timeout 30
                                         (read-line
                                          (uiop:process-info-output child)
                                          nil nil)))
                        (error "History child did not reach append."))))
           (sleep 0.25)
           (funcall check "child writers wait on the stable sibling lock"
                    (every #'uiop:process-alive-p children))
           (sb-posix:close lock-fd)
           (setf lock-fd nil)
           (let ((codes (mapcar #'uiop:wait-process children))
                 (outputs (mapcar
                           (lambda (child)
                             (uiop:slurp-stream-string
                              (uiop:process-info-output child)))
                           children)))
             (funcall check "blocked child writers finish after lock release"
                      (every (lambda (code) (eql 0 code)) codes))
             (funcall check "child writers report no storage errors"
                      (every (lambda (output) (string= "" output)) outputs)))
           (let* ((nshell.infrastructure.persistence::*history-file-path-override*
                    path)
                  (*error-output* (make-string-output-stream))
                  (records
                    (nshell.infrastructure.persistence:load-history-file)))
             (funcall check "serialized appends dedupe identical command text"
                      (let ((texts
                              (mapcar
                               #'nshell.infrastructure.persistence:history-record-text
                               records)))
                        (and (= 3 (length texts))
                             (string= "seed" (first texts))
                             (= 1 (count "shared command" texts :test #'string=))
                             (= 1 (count "distinct command" texts :test #'string=))
                             (string= "" (get-output-stream-string *error-output*))))))
           (funcall check "stable sibling lock is owner-only"
                    (and (probe-file lock-path)
                         (= #o600
                            (logand #o777
                                    (sb-posix:stat-mode
                                     (sb-posix:stat lock-path)))))))
      (when lock-fd
        (sb-posix:close lock-fd))
      (dolist (child children)
        (handler-case
            (progn
              (when (uiop:process-alive-p child)
                (uiop:terminate-process child :urgent t))
              (uiop:wait-process child)
              (uiop:close-streams child))
          (serious-condition (condition)
            (format *error-output* "History child cleanup failed: ~a~%"
                    condition)))))))




(let* ((directory (format nil "/tmp/nshell-history-storage-~d-~36r/"
                          (sb-posix:getpid) (random most-positive-fixnum)))
       (path (merge-pathnames "history" directory))
       (target (merge-pathnames "target" directory))
       (lock-path
         (nshell.infrastructure.persistence::%history-lock-path path))
       (old-mask (sb-posix:umask #o022))
       (checks 0)
       (failures 0))
  (sb-posix:mkdir directory #o700)
  (labels ((check (name result)
             (incf checks)
             (unless result
               (incf failures))
             (format t "~a ~a~%" (if result "PASS" "FAIL") name))
           (contents (file)
             (uiop:read-file-string file))
           (append-command (command)
             (let ((capture (make-string-output-stream)))
               (let ((*error-output* capture))
                 (let ((result
                         (nshell.infrastructure.persistence::append-history-entry
                          command)))
                   (values result (get-output-stream-string capture)))))))
    (unwind-protect
         (let ((nshell.infrastructure.persistence::*history-file-path-override*
                 path))
           (multiple-value-bind (result errors)
               (append-command "first")
             (check "new history file is owner-only"
                    (and result
                         (string= "" errors)
                         (= #o600
                            (logand #o777
                                    (sb-posix:stat-mode (sb-posix:stat path)))))))
           (sb-posix:chmod path #o644)
           (multiple-value-bind (result errors)
               (append-command "second")
             (check "existing history file returns to owner-only mode"
                    (and result
                         (string= "" errors)
                         (= #o600
                            (logand #o777
                                    (sb-posix:stat-mode (sb-posix:stat path)))))))
           (check "valid entries round-trip"
                  (equal '("first" "second")
                         (mapcar
                          #'nshell.infrastructure.persistence:history-record-text
                          (nshell.infrastructure.persistence:load-history-file))))
           (rename-file path target)
           (sb-posix:symlink (namestring target) (namestring path))
           (let ((before (contents target)))
             (multiple-value-bind (result errors)
                 (append-command "symlink")
               (check "symlink append is rejected without changing the target"
                      (and (null result)
                           (plusp (length errors))
                           (string= before (contents target))))))
           (sb-posix:unlink (namestring path))
           (sb-posix:link (namestring target) (namestring path))
           (let ((before (contents target)))
             (multiple-value-bind (result errors)
                 (append-command "hardlink")
               (check "hardlink append is rejected without changing the target"
                      (and (null result)
                           (plusp (length errors))
                           (string= before (contents target))))))
           (delete-file path)
           (delete-file target)
           (multiple-value-bind (result errors)
               (append-command "retained")
             (check "append creates a fresh secured file"
                    (and result (string= "" errors))))
           (with-open-file (stream path :direction :output :if-exists :append)
             (format stream "# nshell-history-v3 100~%short"))
           (let* ((capture (make-string-output-stream))
                  (records
                    (let ((*error-output* capture))
                      (nshell.infrastructure.persistence:load-history-file)))
                  (notice (get-output-stream-string capture)))
             (check "valid prefix survives truncated tail with one notice"
                    (and (equal '("retained")
                                (mapcar
                                 #'nshell.infrastructure.persistence:history-record-text
                                 records))
                         (= 1 (count (code-char 10) notice)))))
           (multiple-value-bind (result errors)
               (append-command "visible")
             (check "append repairs a truncated tail and succeeds"
                    (and result (string= "" errors))))
           (check "append retains recovered prefix and adds new command"
                  (equal '("retained" "visible")
                         (mapcar
                          #'nshell.infrastructure.persistence:history-record-text
                          (nshell.infrastructure.persistence:load-history-file))))
           (check-history-reader-lock path #'check)
           (format t "History storage: ~d checks, ~d failures~%" checks failures))
      (sb-posix:umask old-mask)
      (when (probe-file path)
        (delete-file path))
      (when (probe-file target)
        (delete-file target))
      (when (probe-file lock-path)
        (delete-file lock-path))
      (sb-posix:rmdir directory)))
  (uiop:quit (if (and (plusp checks) (zerop failures)) 0 1)))

