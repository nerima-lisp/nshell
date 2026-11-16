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
