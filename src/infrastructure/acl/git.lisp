(in-package #:nshell.infrastructure.acl)

(defparameter *git-command-timeout* 1
  "Seconds a git prompt probe may run before it is abandoned. The prompt must
never block on a slow, networked, or hung repository, so branch/status queries
are bounded well below *EXTERNAL-COMMAND-TIMEOUT*; on timeout the segment simply
renders as if the directory were not a repository.")

(defvar *git-runner* nil
  "NIL, or a function (DIR ARGS) -> (values OUTPUT EXIT-CODE) substituted for the
real git invocation in tests. A single deterministic function seam, not a
single test seam: tests supply the git result directly rather than faking a
subprocess object with separate spawn/output/exit-code hooks.")

(defvar *git-status-cache* (make-hash-table :test #'equal)
  "Directory keyed cache of git prompt status.")

(defmacro with-git-runner ((runner) &body body)
  "Run BODY with RUNNER, a (DIR ARGS) -> (values OUTPUT EXIT-CODE) function,
standing in for real git invocations."
  `(let ((*git-runner* ,runner))
     ,@body))

(defun clear-git-status-cache ()
  "Clear all cached git prompt status."
  (clrhash *git-status-cache*))

(defun %trim-newline (text)
  (string-right-trim '(#\Newline #\Return #\Space #\Tab) text))

(defun %run-git (dir args)
  "Run git ARGS in DIR with a bounded native subprocess. A timeout, launch
failure, or any error yields (values \"\" 1). Delegates to *GIT-RUNNER* when
one is bound."
  (if *git-runner*
      (funcall *git-runner* dir args)
      (handler-case
          (let* ((environment (current-environment-entries))
                 (program (%resolve-external-command "git" environment)))
            (unless program
              (return-from %run-git (values "" 1)))
            (let ((output (make-string-output-stream))
                  (error-output (make-string-output-stream))
                  (timeout (ensure-timeout-seconds
                            *git-command-timeout* "git command timeout")))
              (let ((process
                      (%spawn-in-own-process-group
                       program
                       (list* "-C"
                              (namestring (host-kit:ensure-directory-pathname dir))
                              args)
                       environment nil :stream :error :stream)))
                (multiple-value-bind (exit timed-out-p)
                    (%wait-process-with-output
                     process output timeout (lambda () 124) error-output)
                  (if timed-out-p
                      (values "" 1)
                      (values (get-output-stream-string output)
                              (or exit 1)))))))
        (error () (values "" 1)))))

(defun %git-branch-uncached (dir)
  (multiple-value-bind (out code) (%run-git dir '("rev-parse" "--abbrev-ref" "HEAD"))
    (when (zerop code)
      (let ((branch (%trim-newline out)))
        (unless (or (string= branch "") (string= branch "HEAD"))
          branch)))))

(defun %git-dirty-uncached (dir)
  (multiple-value-bind (out code) (%run-git dir '("status" "--porcelain" "--untracked-files=no"))
    (and (zerop code) (> (length (%trim-newline out)) 0))))

(defun get-git-status (dir)
  "Return values BRANCH and DIRTY-P for DIR, using a per-directory cache."
  (let* ((key (namestring (host-kit:ensure-directory-pathname dir)))
         (cached (gethash key *git-status-cache*)))
    (if cached
        (values (first cached) (second cached))
        (let* ((branch (%git-branch-uncached key))
               (dirty (and branch (%git-dirty-uncached key))))
          (setf (gethash key *git-status-cache*) (list branch dirty))
          (values branch dirty)))))
