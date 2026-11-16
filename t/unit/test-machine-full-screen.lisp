(in-package #:nshell/test)

;;; ux/U6: under --json a full-screen program stops the run with
;;; E_INTERACTIVE_PROGRAM and the fixes say how to get its output instead. The
;;; command-name table refuses a known program before anything starts.

(defun %full-screen-call-with-programs (names thunk)
  "Call THUNK with a directory holding a stand-in for each of NAMES first on
PATH, and the directory. Each stand-in prints `ran NAME` and creates the file
NAME.ran in the directory, so a test can tell whether it started."
  (host-kit:with-temporary-directory (directory)
    (let ((native (string-right-trim "/" (sb-ext:native-namestring directory))))
      (dolist (name names)
        (let ((path (format nil "~A/~A" native name)))
          (with-open-file (out path :direction :output)
            (format out "#!/bin/sh~%echo ran ~A~%touch '~A/~A.ran'~%" name native name))
          (sb-posix:chmod path #o755)))
      (%noninteractive-call-with-environment
       (list (cons "PATH" (format nil "~A:~A" native (host-kit:getenv "PATH"))))
       (lambda () (funcall thunk native))))))

(defun %full-screen-started-p (directory name)
  (probe-file (format nil "~A/~A.ran" directory name)))

(defparameter +full-screen-top-fix+
  #+darwin "top -l 1"
  #-darwin "top -b -n 1")

(describe "machine full-screen programs"
  (it "refuses a full-screen program before it starts and suggests a fix"
    (with-noninteractive-test-state ()
      (%full-screen-call-with-programs
       '("less" "vim")
       (lambda (directory)
         (loop for (input fix) in '(("less NOTES.txt" "cat NOTES.txt")
                                    ("(less NOTES.txt)" "(cat NOTES.txt)")
                                    ("vim NOTES.txt" "cat NOTES.txt"))
               do (let ((envelope (json-command input)))
                    (expect (json-at envelope "status") :to-equal 6)
                    (expect (json-at envelope "error" "code")
                            :to-equal "E_INTERACTIVE_PROGRAM")
                    (expect (json-at envelope "error" "span" "column")
                            :to-equal (if (char= #\( (char input 0)) 2 1))
                    (expect (json-at envelope "error" "fixes" 0 "input") :to-equal fix)
                    (expect (json-at envelope "error" "fixes" 0 "why") :to-be-truthy)))
         (expect (%full-screen-started-p directory "less") :to-be-falsy)
         (expect (%full-screen-started-p directory "vim") :to-be-falsy)))))

  (it "refuses a pipeline with a full-screen stage before any stage starts"
    (with-noninteractive-test-state ()
      (%full-screen-call-with-programs
       '("less" "first")
       (lambda (directory)
         (loop for (input fix) in '(("first | less" "first | cat")
                                    ("(| (first) (less))" "(| (first) (cat))"))
               do (let ((envelope (json-command input)))
                    (expect (json-at envelope "status") :to-equal 6)
                    (expect (json-at envelope "error" "code")
                            :to-equal "E_INTERACTIVE_PROGRAM")
                    (expect (json-at envelope "error" "fixes" 0 "input") :to-equal fix)))
         (expect (%full-screen-started-p directory "first") :to-be-falsy)
         (expect (%full-screen-started-p directory "less") :to-be-falsy)))))

  (it "refuses a full-screen program started in the background"
    (with-noninteractive-test-state ()
      (%full-screen-call-with-programs
       '("less" "first")
       (lambda (directory)
         (loop for (input fix) in '(("less NOTES.txt &" "cat NOTES.txt &")
                                    ("first | less &" "first | cat &"))
               do (let ((envelope (json-command input)))
                    (expect (json-at envelope "status") :to-equal 6)
                    (expect (json-at envelope "error" "code")
                            :to-equal "E_INTERACTIVE_PROGRAM")
                    (expect (json-at envelope "error" "fixes" 0 "input") :to-equal fix)))
         ;; A background stand-in that did start has written its file by now.
         (sleep 0.5)
         (expect (%full-screen-started-p directory "first") :to-be-falsy)
         (expect (%full-screen-started-p directory "less") :to-be-falsy)))))

  (it "points the span and the fix at the refused command, not an earlier word"
    (with-noninteractive-test-state ()
      (%full-screen-call-with-programs
       '("less")
       (lambda (directory)
         (declare (ignore directory))
         (loop for (input fix line column)
                 in (list '("echo less; less NOTES.txt" "echo less; cat NOTES.txt" 1 12)
                          (list (format nil "echo less~%X=less less NOTES.txt")
                                (format nil "echo less~%X=less cat NOTES.txt")
                                2 8)
                          '("(echo \"less\") (less \"NOTES.txt\")"
                            "(echo \"less\") (cat \"NOTES.txt\")" 1 16))
               do (let ((envelope (json-command input)))
                    (expect (json-at envelope "error" "code")
                            :to-equal "E_INTERACTIVE_PROGRAM")
                    (expect (json-at envelope "error" "span" "line") :to-equal line)
                    (expect (json-at envelope "error" "span" "column") :to-equal column)
                    (expect (json-at envelope "error" "span" "end") :to-equal (+ column 4))
                    (expect (json-at envelope "error" "fixes" 0 "input") :to-equal fix)))))))

  (it "replaces the command name as written, not a same-named argument"
    (with-noninteractive-test-state ()
      (%full-screen-call-with-programs
       '("less")
       (lambda (directory)
         (declare (ignore directory))
         (loop for (input fix column end)
                 in '(("^less less" "cat less" 1 6)
                      ("l\"ess\" less" "cat less" 1 7)
                      ("(^less \"less\")" "(cat \"less\")" 2 7))
               do (let ((envelope (json-command input)))
                    (expect (json-at envelope "error" "code")
                            :to-equal "E_INTERACTIVE_PROGRAM")
                    (expect (list (json-at envelope "error" "span" "line")
                                  (json-at envelope "error" "span" "column")
                                  (json-at envelope "error" "span" "end"))
                            :to-equal (list 1 column end))
                    (expect (json-at envelope "error" "fixes" 0 "input") :to-equal fix)))))))

  (it "gives no span or fix for a program refused in a sourced file"
    (with-noninteractive-test-state ()
      (%full-screen-call-with-programs
       '("less")
       (lambda (directory)
         (let ((script (format nil "~A/script.nsh" directory)))
           (with-open-file (out script :direction :output)
             (format out "less NOTES.txt~%"))
           (let ((envelope (json-command (format nil "echo less; source ~A" script))))
             (expect (json-at envelope "error" "code") :to-equal "E_INTERACTIVE_PROGRAM")
             (expect (json-at envelope "error" "span") :to-be-null)
             (expect (json-at envelope "error" "fixes") :to-be-null)))))))

  (it "suggests the noninteractive form of man and top"
    (with-noninteractive-test-state ()
      (%full-screen-call-with-programs
       '("man" "top")
       (lambda (directory)
         (declare (ignore directory))
         (loop for (input fix) in (list '("man ls" "man -P cat ls")
                                        (list "top" +full-screen-top-fix+))
               do (let ((envelope (json-command input)))
                    (expect (json-at envelope "error" "code")
                            :to-equal "E_INTERACTIVE_PROGRAM")
                    (expect (json-at envelope "error" "fixes" 0 "input")
                            :to-equal fix)))))))

  (it "runs the noninteractive forms of programs in the table"
    (with-noninteractive-test-state ()
      (%full-screen-call-with-programs
       '("man" "top" "emacs" "vim" "less")
       (lambda (directory)
         (declare (ignore directory))
         (loop for (input name) in (list (list "man -P cat ls" "man")
                                         (list +full-screen-top-fix+ "top")
                                         (list "emacs --batch --eval t" "emacs")
                                         (list "vim -es" "vim")
                                         (list "less --version" "less"))
               do (let ((envelope (json-command input)))
                    (expect (json-at envelope "status") :to-equal 0)
                    (expect (json-at envelope "stdout" "text")
                            :to-equal (format nil "ran ~A~%" name))))))))

  (it "leaves full-screen programs alone outside machine mode"
    (with-noninteractive-test-state ()
      (%full-screen-call-with-programs
       '("less")
       (lambda (directory)
         (expect (%noninteractive-batch-output "less NOTES.txt")
                 :to-equal (format nil "ran less~%"))
         (expect (%full-screen-started-p directory "less") :to-be-truthy))))))

(defun %full-screen-alternate-screen-run (script &key (wrap "~A"))
  "Run the sh SCRIPT under --json with a 20 s deadline, after it records its
pid, as the command WRAP makes of `sh -c 'SCRIPT'`. Return the envelope, the
seconds the run took, and whether the sh process is gone afterwards."
  (host-kit:with-temporary-directory (directory)
    (let* ((pid-file (sb-ext:native-namestring (merge-pathnames "pid" directory)))
           (command (format nil "sh -c 'echo $$ > ~A; ~A'" pid-file script)))
      (multiple-value-bind (envelope status seconds)
          (json-command (format nil wrap command) :timeout 20)
        (declare (ignore status))
        (let ((pid (parse-integer (uiop:read-file-string pid-file) :junk-allowed t)))
          (values envelope seconds (null (json-wait-until-dead (list pid) 5))))))))

(describe "machine alternate screen"
  (it "stops a program that switches to the alternate screen, well before the deadline"
    (with-noninteractive-test-state ()
      (dolist (wrap '("~A" "~A | cat"))
        (multiple-value-bind (envelope seconds stopped-p)
            (%full-screen-alternate-screen-run
             "printf \"before\\n\"; printf \"\\033[?1049h\"; sleep 30" :wrap wrap)
          (expect (json-at envelope "status") :to-equal 6)
          (expect (json-at envelope "error" "code") :to-equal "E_INTERACTIVE_PROGRAM")
          (expect (json-at envelope "stdout" "text") :to-equal (format nil "before~%"))
          (expect seconds :to-be-less-than 5)
          (expect stopped-p :to-be-truthy)))))

  (it "stops a program that switches on its standard error"
    (with-noninteractive-test-state ()
      (dolist (wrap '("~A" "~A | cat"))
        (multiple-value-bind (envelope seconds stopped-p)
            (%full-screen-alternate-screen-run
             "printf \"\\033[?1049h\" >&2; sleep 30" :wrap wrap)
          (expect (json-at envelope "error" "code") :to-equal "E_INTERACTIVE_PROGRAM")
          (expect seconds :to-be-less-than 5)
          (expect stopped-p :to-be-truthy)))))

  (it "stops a program run with an environment assignment, on either output"
    (with-noninteractive-test-state ()
      (dolist (script '("printf \"\\033[?1049h\"; sleep 30"
                        "printf \"\\033[?1049h\" >&2; sleep 30"))
        (multiple-value-bind (envelope seconds stopped-p)
            (%full-screen-alternate-screen-run script :wrap "X=1 ~A")
          (expect (json-at envelope "error" "code") :to-equal "E_INTERACTIVE_PROGRAM")
          (expect seconds :to-be-less-than 5)
          (expect stopped-p :to-be-truthy)))))

  (it "finds the sequence when it arrives in two writes"
    (with-noninteractive-test-state ()
      (multiple-value-bind (envelope seconds stopped-p)
          (%full-screen-alternate-screen-run
           "printf \"\\033[?10\"; sleep 0.3; printf \"49h\"; sleep 30")
        (expect (json-at envelope "error" "code") :to-equal "E_INTERACTIVE_PROGRAM")
        (expect seconds :to-be-less-than 5)
        (expect stopped-p :to-be-truthy))))

  (it "lets other escape sequences through"
    (with-noninteractive-test-state ()
      (multiple-value-bind (envelope seconds)
          (%full-screen-alternate-screen-run
           "printf \"\\033[?1049l\\033[?1000h\\033[31mred\\033[0m\\n\"")
        (expect (json-at envelope "status") :to-equal 0)
        (expect (json-at envelope "stdout" "text") :to-equal (format nil "red~%"))
        (expect seconds :to-be-less-than 5)))))

(describe "machine full-screen option spellings"
  (it "runs vim with -e and -s as separate words"
    (with-noninteractive-test-state ()
      (%full-screen-call-with-programs
       '("vim")
       (lambda (directory)
         (declare (ignore directory))
         (let ((envelope (json-command "vim -u NONE -i NONE -e -s -c 'qa!'")))
           (expect (json-at envelope "status") :to-equal 0)
           (expect (json-at envelope "stdout" "text") :to-equal (format nil "ran vim~%")))))))

  (it "takes each noninteractive spelling of an option as noninteractive"
    (dolist (command '(("vim" "-u" "NONE" "-e" "-s" "-c" "qa!")
                       ("vi" "-E" "-s")
                       ("nvim" "-e" "-c" "qa!" "-s")
                       ("nvim" "-u" "NONE" "--headless")
                       ("emacs" "-Q" "--batch" "--eval" "t")
                       ("emacs" "--script=build.el")
                       ("emacs" "-version")
                       ("man" "-Pcat" "ls")
                       ("man" "--pager=cat" "ls")
                       ("man" "--pager" "cat" "ls")
                       ("man" "--whatis" "ls")
                       ("man" "--apropos" "ls")
                       ("man" "--where" "ls")
                       ("man" "--path" "ls")
                       ("top" "-l1")
                       ("top" "-l" "1")
                       ("top" "-bn1")
                       ("top" "-n" "1" "-b")
                       ("top" "--batch-mode")
                       ("less" "-V")))
      (expect (cons command
                    (nshell.feature.machine:full-screen-program-kind
                     (first command) (rest command)))
              :to-equal (list command))))

  (it "still refuses the interactive spellings"
    (dolist (command '(("vim" "-e" "NOTES.txt")
                       ("vim" "-s" "keys.vim" "NOTES.txt")
                       ("vim" "-s" "-e")
                       ("emacs" "-nw" "NOTES.txt")
                       ("emacs" "--batchless")
                       ("man" "ls")
                       ("top" "-o" "cpu")))
      (expect (nshell.feature.machine:full-screen-program-kind
               (first command) (rest command))
              :to-be-truthy))))
