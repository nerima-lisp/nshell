(in-package #:nshell.infrastructure.acl)

(defvar *git-process-fns* nil
  "Process adapter plist used by git prompt probes.")

(defvar *git-status-cache* (make-hash-table :test #'equal)
  "Directory keyed cache of git prompt status.")

(defmacro with-git-process-fns ((process-fns) &body body)
  "Run BODY with PROCESS-FNS used for git subprocesses."
  `(let ((*git-process-fns* ,process-fns))
     ,@body))

(defun clear-git-status-cache ()
  "Clear all cached git prompt status."
  (clrhash *git-status-cache*))

(defun %git-process-fn (key fallback)
  (or (getf *git-process-fns* key) fallback))

(defun %trim-newline (text)
  (string-right-trim '(#\Newline #\Return #\Space #\Tab) text))

(defun %read-all-lines (stream)
  (with-output-to-string (out)
    (loop for line = (read-line stream nil nil)
          while line
          do (progn (write-string line out) (terpri out)))))

(defun %run-git (dir args)
  "Run git ARGS in DIR through the configured process adapter.
Returns two values: output string and exit code."
  (handler-case
      (let* ((spawn (%git-process-fn :spawn #'spawn-async))
             (exit-code (%git-process-fn :exit-code #'sb-ext:process-exit-code))
             (output (%git-process-fn :output #'sb-ext:process-output))
             (proc (funcall spawn "git" (append (list "-C" (namestring (uiop:ensure-directory-pathname dir))) args)
                            :output :stream
                            :error nil
                            :wait t
                            :process-group nil)))
        (if proc
            (progn
              (values (let ((stream (funcall output proc)))
                        (if stream (%read-all-lines stream) ""))
                      (or (funcall exit-code proc) 0)))
            (values "" 1)))
    (error () (values "" 1))))

(defun %git-branch-uncached (dir)
  (multiple-value-bind (out code) (%run-git dir '("rev-parse" "--abbrev-ref" "HEAD"))
    (when (zerop code)
      (let ((branch (%trim-newline out)))
        (unless (or (string= branch "") (string= branch "HEAD"))
          branch)))))

(defun %git-dirty-uncached (dir)
  (multiple-value-bind (out code) (%run-git dir '("status" "--porcelain"))
    (and (zerop code) (> (length (%trim-newline out)) 0))))

(defun get-git-status (dir)
  "Return values BRANCH and DIRTY-P for DIR, using a per-directory cache."
  (let* ((key (namestring (uiop:ensure-directory-pathname dir)))
         (cached (gethash key *git-status-cache*)))
    (if cached
        (values (first cached) (second cached))
        (let* ((branch (%git-branch-uncached key))
               (dirty (and branch (%git-dirty-uncached key))))
          (setf (gethash key *git-status-cache*) (list branch dirty))
          (values branch dirty)))))

