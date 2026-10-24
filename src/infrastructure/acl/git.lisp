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
(defvar *git-status-cache-lock* (sb-thread:make-mutex :name "git prompt status cache"))
(defvar *git-status-worker-launcher* nil
  "Optional test hook for scheduling a Git status worker.")

(defmacro with-git-runner ((runner) &body body)
  "Run BODY with RUNNER, a (DIR ARGS) -> (values OUTPUT EXIT-CODE) function,
synchronously for deterministic tests."
  `(let ((*git-runner* ,runner)
         (*git-status-worker-launcher* #'funcall))
     ,@body))

(defun clear-git-status-cache ()
  "Clear all cached git prompt status."
  (sb-thread:with-mutex (*git-status-cache-lock*)
    (clrhash *git-status-cache*)))

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
  "Return cached Git status and refresh cache misses outside the prompt thread."
  (let ((key (namestring (host-kit:ensure-directory-pathname dir)))
        (cached nil)
        (found-p nil))
    (sb-thread:with-mutex (*git-status-cache-lock*)
      (multiple-value-setq (cached found-p) (gethash key *git-status-cache*))
      (unless found-p
        (setf (gethash key *git-status-cache*) (cons :pending nil))))
    (labels ((publish (branch dirty-p)
               (sb-thread:with-mutex (*git-status-cache-lock*)
                 (setf (gethash key *git-status-cache*)
                       (list branch dirty-p))))
             (read-current ()
               (sb-thread:with-mutex (*git-status-cache-lock*)
                 (multiple-value-bind (entry present-p)
                     (gethash key *git-status-cache*)
                   (if (and present-p
                            (not (and (consp entry)
                                      (eq (car entry) :pending))))
                       (values (first entry) (second entry))
                       (values nil nil))))))
      (cond
        (found-p
         (if (and (consp cached) (eq (car cached) :pending))
             (values nil nil)
             (values (first cached) (second cached))))
        (t
         (let* ((runner *git-runner*)
                (worker
                  (lambda ()
                    (let ((*git-runner* runner))
                      (let* ((branch (%git-branch-uncached key))
                             (dirty-p (and branch (%git-dirty-uncached key))))
                        (publish branch dirty-p))))))
           (if *git-status-worker-launcher*
               (funcall *git-status-worker-launcher* worker)
               (handler-case
                   (sb-thread:make-thread worker
                                          :name "nshell git prompt status")
                 (error () (publish nil nil))))
           (read-current)))))))
