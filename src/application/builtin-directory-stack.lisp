(in-package #:nshell.application)

;;; `dirs` / `pushd` / `popd` (fish's directory stack). The shell context has
;;; no slot for it, so it lives in a special, like the other application-level
;;; session state.

(defvar *directory-stack* nil
  "Stack of directories pushed by `pushd`, most-recently-pushed first.")

(defun %directory-stack-tilde-collapse (path environment)
  "Collapse a leading $HOME in PATH to ~, the way `dirs` and the prompt do.
HOME defaults to \"/\" (see %MAKE-DEFAULT-ENVIRONMENT-VAR-TABLE), so a bare
STRING-PREFIX-P check would treat every absolute path as HOME-relative;
excluding \"/\" and requiring a directory boundary after the prefix (not just
a textual one, so \"/home\" doesn't swallow \"/home2\") avoids that."
  (let ((home (and environment (nshell.domain.environment:env-get environment "HOME"))))
    (cond
      ((or (null home) (string= home "") (string= home "/")) path)
      ((string= path home) "~")
      ((and (> (length path) (length home))
            (string-prefix-p home path)
            (char= (char path (length home)) #\/))
       (concatenate 'string "~" (subseq path (length home))))
      (t path))))

(defun %directory-stack-chdir (context target)
  "Change directory to TARGET, updating OLDPWD/PWD like `cd`. Returns the new
working directory."
  (let* ((environment (shell-context-environment context))
         (old-cwd
           (%logical-current-directory
            environment
            (ignore-errors (host-kit:getcwd))))
         (new-cwd (%normalize-directory-path target old-cwd)))
    (host-kit:chdir new-cwd)
    (%update-directory-environment context environment old-cwd new-cwd)
    new-cwd))

(defun %dirs-format-stack (context)
  (let ((environment (shell-context-environment context)))
    (format nil "~{~a~^ ~}~%"
            (mapcar (lambda (path) (%directory-stack-tilde-collapse path environment))
                    (cons
                      (%logical-current-directory
                       environment
                       (ignore-errors (host-kit:getcwd)))
                      *directory-stack*)))))

(define-builtin %builtin-dirs (context args) ()
  (if args
      (%builtin-usage "dirs" "dirs" 2)
      (values (%dirs-format-stack context) 0)))

(define-builtin %builtin-pushd (context args) ()
  (cond
    ((rest args) (%builtin-usage "pushd" "pushd [DIRECTORY]" 2))
    (args
     (let ((current
             (%logical-current-directory
              (shell-context-environment context)
              (ignore-errors (host-kit:getcwd)))))
       (handler-case
           (progn
             (%directory-stack-chdir context (first args))
             (push current *directory-stack*)
             (values nil 0))
         (error (condition) (values (format nil "pushd: ~a~%" condition) 1)))))
    ((null *directory-stack*)
     (values (format nil "pushd: no other directory~%") 1))
    (t
     (let ((target (first *directory-stack*))
           (current
             (%logical-current-directory
              (shell-context-environment context)
              (ignore-errors (host-kit:getcwd)))))
       (handler-case
           (progn
             (%directory-stack-chdir context target)
             (setf *directory-stack* (cons current (rest *directory-stack*)))
             (values nil 0))
         (error (condition) (values (format nil "pushd: ~a~%" condition) 1)))))))

(define-builtin %builtin-popd (context args) ()
  (cond
    (args (%builtin-usage "popd" "popd" 2))
    ((null *directory-stack*)
     (values (format nil "popd: directory stack empty~%") 1))
    (t
     (let ((target (first *directory-stack*)))
       (handler-case
           (progn
             (%directory-stack-chdir context target)
             (pop *directory-stack*)
             (values nil 0))
         (error (condition) (values (format nil "popd: ~a~%" condition) 1)))))))
