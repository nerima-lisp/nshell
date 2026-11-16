(in-package #:nshell.feature.machine)

;;; ux/U6 「非対話で詰まらないように」: what machine mode and NSHELL_AGENT=1
;;; batch runs give the programs they start.

(defparameter +noninteractive-child-environment+
  '(("PAGER" . "cat")
    ("GIT_PAGER" . "cat")
    ("TERM" . "dumb")
    ("NO_COLOR" . "1"))
  "Exported variables a noninteractive run starts from, as (NAME . VALUE). They
replace what the caller's environment holds; the input can still set another
value, for one command or for the rest of the run.")

;;; Full-screen programs (E_INTERACTIVE_PROGRAM). Each entry is (NAME KIND
;;; . NONINTERACTIVE): KIND chooses the fix, and NONINTERACTIVE lists the
;;; arguments with which NAME runs without a terminal, matched as a whole
;;; argument or, for a string ending in *, as its prefix. --version runs
;;; without one for every program.

(defparameter +full-screen-programs+
  '(("vi" :editor "-es" "-Es")
    ("vim" :editor "-es" "-Es")
    ("nvim" :editor "-es" "-Es" "--headless")
    ("nano" :editor)
    ("emacs" :editor "--batch" "-batch" "--script" "-script")
    ("less" :pager)
    ("more" :pager)
    ("most" :pager)
    ("man" :manual "-P" "-f" "-k" "-w")
    ("top" :top "-l*" "-b*")
    ("htop" :monitor)
    ("btop" :monitor)
    ("watch" :watch)))

(defun %command-base-name (command)
  (subseq command (1+ (or (position #\/ command :from-end t) -1))))

(defun %noninteractive-argument-p (patterns argument)
  (or (string= argument "--version")
      (some (lambda (pattern)
              (let ((end (1- (length pattern))))
                (if (char= #\* (char pattern end))
                    (and (>= (length argument) end)
                         (string= pattern argument :end1 end :end2 end))
                    (string= pattern argument))))
            patterns)))

(defun full-screen-program-kind (command arguments)
  "Return the kind of full-screen program COMMAND is when run with the strings
ARGUMENTS, or NIL when it is not one or those arguments run it without a
terminal. COMMAND may be a path."
  (destructuring-bind (&optional kind &rest patterns)
      (rest (assoc (%command-base-name command) +full-screen-programs+
                   :test #'string=))
    (and kind
         (notany (lambda (argument) (%noninteractive-argument-p patterns argument))
                 arguments)
         kind)))

(defparameter +top-sample-command+
  #+darwin "top -l 1"
  #-darwin "top -b -n 1"
  "top printing one sample and exiting, as this platform's top spells it.")

(defun full-screen-program-replacement (command arguments)
  "Return the text to write in place of the full-screen program COMMAND (the
word itself, ARGUMENTS following it unchanged) for a run that gives the same
output without a terminal, and why, or NIL when there is no such text."
  (let ((operands-p (and arguments
                         (notany (lambda (argument)
                                   (and (plusp (length argument))
                                        (char= #\- (char argument 0))))
                                 arguments))))
    (case (full-screen-program-kind command arguments)
      (:pager
       (when (or operands-p (null arguments))
         (values "cat" "cat prints the text without a pager")))
      (:editor
       (when operands-p
         (values "cat" "cat prints the file; change it with a noninteractive tool such as sed")))
      (:manual
       (values "man -P cat" "man -P cat prints the page without a pager"))
      (:top
       (values +top-sample-command+ "top prints one sample and exits"))
      (:monitor
       (unless arguments
         (values "ps aux" "ps prints the processes once"))))))
