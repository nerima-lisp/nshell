(in-package #:nshell.application)

;;; `dirs` / `pushd` / `popd` / `prevd` / `nextd` (fish's directory stack and
;;; directory history). There is no natural shell-context slot for either --
;;; shell-context.lisp is owned by another agent -- so both live as specials
;;; here, matching how *LAST-EXIT-CODE*'s presentation-layer counterparts and
;;; other application-level session state already work.

(defvar *directory-stack* nil
  "Stack of directories pushed by `pushd`, most-recently-pushed first.")

(defvar *directory-history* nil
  "Directories visited via `cd`, `pushd`, or `popd`, oldest first.
*DIRECTORY-HISTORY-INDEX* tracks the current position for `prevd`/`nextd`;
moving through history does not itself append to this list.")

(defvar *directory-history-index* 0
  "Index of the current directory within *DIRECTORY-HISTORY*.")

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

(defun %directory-stack-record-cd (old-cwd new-cwd)
  "Append NEW-CWD to *DIRECTORY-HISTORY* as the current position, discarding
any forward (redo) entries left over from a previous `prevd`. `cd` should call
this too (see this agent's report for the one-line hook builtin-commands.lisp
needs) so `prevd`/`nextd` see every directory the session has visited."
  (let ((old (namestring old-cwd))
        (new (namestring new-cwd)))
    (when (null *directory-history*)
      (setf *directory-history* (list old)
            *directory-history-index* 0))
    (setf *directory-history*
          (append (subseq *directory-history* 0 (1+ *directory-history-index*))
                  (list new)))
    (setf *directory-history-index* (1- (length *directory-history*)))))

(defun %directory-stack-chdir (context target &key (record-p t))
  "Change directory to TARGET, updating OLDPWD/PWD like `cd`. Returns the new
working directory. RECORD-P is NIL for `prevd`/`nextd`, which move the
existing history pointer rather than extending the history."
  (let* ((environment (shell-context-environment context))
         (old-cwd (host-kit:getcwd)))
    (host-kit:chdir target)
    (let ((new-cwd (host-kit:getcwd)))
      (%update-directory-environment context environment old-cwd new-cwd)
      (when record-p
        (%directory-stack-record-cd old-cwd new-cwd))
      new-cwd)))

(defun %dirs-format-stack (context)
  (let ((environment (shell-context-environment context)))
    (format nil "~{~a~^ ~}~%"
            (mapcar (lambda (path) (%directory-stack-tilde-collapse path environment))
                    (cons (namestring (host-kit:getcwd)) *directory-stack*)))))

(define-builtin %builtin-dirs (context args) ()
  (if args
      (%builtin-usage "dirs" "dirs" 2)
      (values (%dirs-format-stack context) 0)))

(define-builtin %builtin-pushd (context args) ()
  (cond
    ((rest args) (%builtin-usage "pushd" "pushd [DIRECTORY]" 2))
    (args
     (let ((current (namestring (host-kit:getcwd))))
       (handler-case
           (progn
             (%directory-stack-chdir context (first args))
             (push current *directory-stack*)
             (values nil 0))
         (error (condition) (values (format nil "pushd: ~a~%" condition) 1)))))
    ((null *directory-stack*)
     (values (format nil "pushd: no other directory~%") 1))
    (t
     ;; No-arg pushd swaps the current directory with the top of the stack.
     (let ((target (first *directory-stack*))
           (current (namestring (host-kit:getcwd))))
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

(defun %directory-history-step-count (args default)
  (if args
      (or (ignore-errors (parse-integer (first args) :junk-allowed nil)) default)
      default))

(defun %directory-history-move (context delta command)
  (if (null *directory-history*)
      (values (format nil "~a: no directory history~%" command) 1)
      (let ((target-index (max 0 (min (1- (length *directory-history*))
                                      (+ *directory-history-index* delta)))))
        (if (= target-index *directory-history-index*)
            (values (format nil "~a: no ~:[previous~;next~] directory~%"
                            command (plusp delta))
                    1)
            (handler-case
                (progn
                  (%directory-stack-chdir
                   context (nth target-index *directory-history*) :record-p nil)
                  (setf *directory-history-index* target-index)
                  (values nil 0))
              (error (condition) (values (format nil "~a: ~a~%" command condition) 1)))))))

(define-builtin %builtin-prevd (context args) ()
  (%directory-history-move context (- (%directory-history-step-count args 1)) "prevd"))

(define-builtin %builtin-nextd (context args) ()
  (%directory-history-move context (%directory-history-step-count args 1) "nextd"))
