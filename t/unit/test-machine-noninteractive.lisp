(in-package #:nshell/test)

;;; ux/U6 「非対話で詰まらないように」 and proposal/02 「非対話時は決定的に」:
;;; machine mode (--json) and NSHELL_AGENT=1 batch runs give children
;;; PAGER=cat, GIT_PAGER=cat, TERM=dumb, NO_COLOR=1 and /dev/null as stdin,
;;; and turn nshell's own color off. Every other batch run and the interactive
;;; shell keep what they inherit.

(defparameter +noninteractive-test-environment+
  '(("PAGER" . "less") ("GIT_PAGER" . "less -R") ("TERM" . "xterm-256color")
    ("NO_COLOR" . nil))
  "The caller environment the tests start from: a terminal user's pager and
terminal, and no NO_COLOR.")

(defun %noninteractive-call-with-environment (pairs thunk)
  "Call THUNK with each (NAME . VALUE) of PAIRS set in the process environment
(unset when VALUE is NIL), and restore the previous values afterwards."
  (let ((saved (mapcar (lambda (pair) (cons (car pair) (host-kit:getenv (car pair))))
                       pairs)))
    (flet ((apply-pairs (pairs)
             (loop for (name . value) in pairs
                   do (if value
                          (sb-posix:setenv name value 1)
                          (sb-posix:unsetenv name)))))
      (unwind-protect
           (progn (apply-pairs pairs) (funcall thunk))
        (apply-pairs saved)))))

(defun %noninteractive-call-with-standard-input (text thunk)
  "Call THUNK with this process's file descriptor 0 reading TEXT from a pipe,
so a child that inherits fd 0 reads TEXT, and restore fd 0 afterwards."
  (let ((saved (sb-posix:dup 0))
        (octets (sb-ext:string-to-octets text :external-format :utf-8)))
    (multiple-value-bind (read-fd write-fd) (sb-posix:pipe)
      (unwind-protect
           (progn
             (sb-sys:with-pinned-objects (octets)
               (sb-unix:unix-write write-fd octets 0 (length octets)))
             (sb-posix:close write-fd)
             (setf write-fd nil)
             (sb-posix:dup2 read-fd 0)
             (funcall thunk))
        (sb-posix:dup2 saved 0)
        (sb-posix:close saved)
        (sb-posix:close read-fd)
        (when write-fd (sb-posix:close write-fd))))))

(defmacro with-noninteractive-test-state (() &body body)
  "Run BODY with the caller environment of +NONINTERACTIVE-TEST-ENVIRONMENT+
and the specials a batch run may set isolated from the rest of the image."
  `(%noninteractive-call-with-environment
    +noninteractive-test-environment+
    (lambda ()
      (with-repl-test-state
        (let ((nshell.presentation::*noninteractive-batch-p* nil)
              (nshell.infrastructure.acl::*detach-child-standard-input* nil)
              (nshell.infrastructure.terminal:*terminal-color-depth* nil)
              (nshell.infrastructure.acl:*exported-environment* nil))
          ,@body)))))

(defun %noninteractive-batch-output (line)
  "Run LINE through the --command batch path and return what it wrote to
standard output. Standard error is a string stream, not a broadcast stream,
for the reason %SAFE-TEST-INVOKE-MAIN gives."
  (with-output-to-string (*standard-output*)
    (let ((*error-output* (make-string-output-stream)))
      (nshell.presentation:run-repl-batch :line line))))

(defun %noninteractive-main-output (arguments)
  "Run MAIN in this process with ARGUMENTS and return its standard output."
  (let ((nshell::*main-exit-function*
          (lambda (&key unix-status &allow-other-keys) unix-status)))
    (with-output-to-string (*standard-output*)
      (let ((*error-output* (make-string-output-stream)))
        (with-temporary-functions
            (('nshell::%current-process-arguments (lambda () arguments)))
          (nshell::main))))))

(defparameter +noninteractive-printenv+
  "printenv PAGER GIT_PAGER TERM NO_COLOR")

(defparameter +noninteractive-child-defaults-output+
  (format nil "cat~%cat~%dumb~%1~%"))

(defparameter +noninteractive-inherited-output+
  (format nil "less~%less -R~%xterm-256color~%"))

(describe "machine noninteractive defaults"
  (it "gives --json children PAGER=cat, GIT_PAGER=cat, TERM=dumb and NO_COLOR=1"
    (with-noninteractive-test-state ()
      (dolist (input (list +noninteractive-printenv+
                           (format nil "(~A)" +noninteractive-printenv+)))
        (let ((envelope (json-command input)))
          (expect (json-at envelope "stdout" "text")
                  :to-equal +noninteractive-child-defaults-output+)))))

  (it "lets the --json input override a default for one command"
    (with-noninteractive-test-state ()
      (let ((envelope (json-command "PAGER=more printenv PAGER")))
        (expect (json-at envelope "stdout" "text") :to-equal (format nil "more~%")))))

  (it "gives --json children /dev/null as standard input"
    (with-noninteractive-test-state ()
      (%noninteractive-call-with-standard-input
       (format nil "from the caller~%")
       (lambda ()
         (dolist (input '("cat" "cat | cat" "(cat)" "(| (cat) (cat))"))
           (let ((envelope (json-command input)))
             (expect (json-at envelope "status") :to-equal 0)
             (expect (json-at envelope "stdout" "text") :to-equal "")))))))

  (it "keeps an explicit input redirection under --json"
    (with-noninteractive-test-state ()
      (host-kit:with-temporary-directory (directory)
        (let ((path (sb-ext:native-namestring (merge-pathnames "in.txt" directory))))
          (with-open-file (out path :direction :output)
            (write-line "from the file" out))
          (%noninteractive-call-with-standard-input
           (format nil "from the caller~%")
           (lambda ()
             (let ((envelope (json-command (format nil "cat < ~A" path))))
               (expect (json-at envelope "stdout" "text")
                       :to-equal (format nil "from the file~%")))))))))

  (it "turns nshell's own color off in a noninteractive batch run"
    (with-noninteractive-test-state ()
      (let ((nshell.presentation::*noninteractive-batch-p* t))
        (%noninteractive-batch-output "true")
        (expect (nshell.infrastructure.terminal:terminal-color-depth) :to-equal :none)
        (expect (nshell.infrastructure.terminal:ansi-style-sequence
                 :foreground '(:named 1))
                :to-equal ""))))

  (it "gives NSHELL_AGENT=1 batch children the same defaults"
    (with-noninteractive-test-state ()
      (%noninteractive-call-with-environment
       '(("NSHELL_AGENT" . "1"))
       (lambda ()
         (expect (%noninteractive-main-output (list "--command" +noninteractive-printenv+))
                 :to-equal +noninteractive-child-defaults-output+)
         (%noninteractive-call-with-standard-input
          (format nil "from the caller~%")
          (lambda ()
            (expect (%noninteractive-main-output (list "--command" "cat | cat"))
                    :to-equal "")))))))

  (it "leaves a batch run without NSHELL_AGENT and the interactive start as they were"
    (with-noninteractive-test-state ()
      (%noninteractive-call-with-environment
       '(("NSHELL_AGENT" . nil))
       (lambda ()
         (expect (%noninteractive-main-output (list "--command" +noninteractive-printenv+))
                 :to-equal +noninteractive-inherited-output+)
         (expect (%noninteractive-batch-output +noninteractive-printenv+)
                 :to-equal +noninteractive-inherited-output+)
         (%noninteractive-call-with-standard-input
          (format nil "from the caller~%")
          (lambda ()
            (expect (%noninteractive-batch-output "cat | cat")
                    :to-equal (format nil "from the caller~%"))))
         (expect (eq (nshell.infrastructure.terminal:terminal-color-depth) :none)
                 :to-be-falsy)))
      ;; The interactive start never applies the defaults, even when asked to.
      (with-safe-session-state ()
        (let ((nshell.presentation::*noninteractive-batch-p* t))
          (%safe-test-initialize :load-config-p nil :history-p nil)
          (expect (nshell.domain.environment:env-get
                   nshell.presentation::*environment* "PAGER")
                  :to-equal "less")
          (expect (nshell.domain.environment:env-get
                   nshell.presentation::*environment* "TERM")
                  :to-equal "xterm-256color")
          (expect nshell.infrastructure.acl::*detach-child-standard-input*
                  :to-be-null))))))
