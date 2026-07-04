(in-package #:nshell/test)

(in-suite prompt-tests)

(test prompt-raw-constructors-are-internal-boundaries
  (let ((pm (nshell.domain.prompting:make-prompt-model
             :hostname "h"
             :cwd "/repo/"
             :segments (list (nshell.domain.prompting:make-prompt-segment "h" :host))))
        (segment (nshell.domain.prompting:make-prompt-segment "main" :git)))
    (is (string= "h" (nshell.domain.prompting:prompt-hostname pm)))
    (is (equal '("h" . :host)
               (first (nshell.domain.prompting:render-prompt-model pm))))
    (is (string= "main" (nshell.domain.prompting:prompt-segment-text segment)))
    (is (eq :git (nshell.domain.prompting:prompt-segment-kind segment)))
    (is (fboundp 'nshell.domain.prompting::%make-prompt-model))
    (is (fboundp 'nshell.domain.prompting::%make-prompt-segment))))

(test git-segment-resolves-branch-and-dirty-marker
  "A :git segment is resolved through the domain git status resolver."
  (let ((nshell.domain.prompting:*git-status-resolver*
          (lambda (dir)
            (is (string= "/repo/" dir))
            (values "main" t))))
    (let* ((pm (nshell.domain.prompting:make-prompt-model
                :hostname "h"
                :cwd "/repo/"
                :directory "/repo/"
                :right-segments (list (nshell.domain.prompting:make-prompt-segment "" :git))))
           (result (nshell.domain.prompting:render-right-prompt-model pm)))
      (is (equal '("main*" . :git) (first result))))))

(test default-right-prompt-includes-git-and-exit-code
  "Default right prompt displays git status and non-zero exit code."
  (let ((nshell.domain.prompting:*git-status-resolver*
          (lambda (dir)
            (declare (ignore dir))
            (values "feature" nil))))
    (let* ((pm (nshell.domain.prompting:make-prompt-model
                :hostname "h" :cwd "/repo/" :directory "/repo/" :exit-code 2))
           (result (nshell.domain.prompting:render-right-prompt-model pm)))
      (is (equal '("feature" . :git) (first result)))
      (is (equal '(" " . :literal) (second result)))
      (is (equal '("[2]" . :exit-error) (third result))))))

(test default-right-prompt-appends-duration-and-time
  "Default right prompt includes duration and time segments after status information."
  (let ((nshell.domain.prompting:*git-status-resolver*
          (lambda (dir)
            (declare (ignore dir))
            (values "feature" nil)))
        (nshell.domain.prompting:*prompt-time-resolver*
          (lambda ()
            "12:34")))
    (let* ((pm (nshell.domain.prompting:make-prompt-model
                :hostname "h"
                :cwd "/repo/"
                :directory "/repo/"
                :exit-code 2
                :duration-ms 123))
           (result (nshell.domain.prompting:render-right-prompt-model pm)))
      (is (= 7 (length result)))
      (is (equal '("feature" . :git) (first result)))
      (is (equal '(" " . :literal) (second result)))
      (is (equal '("[2]" . :exit-error) (third result)))
      (is (equal '(" " . :literal) (fourth result)))
      (is (equal '("123ms" . :duration) (fifth result)))
      (is (equal '(" " . :literal) (sixth result)))
      (is (equal '("12:34" . :time) (seventh result))))))

(test git-status-uses-process-adapter-and-cache
  "Git status is executed through the supplied process adapter and cached per directory."
  (let ((calls nil))
    (nshell.infrastructure.acl:clear-git-status-cache)
    (nshell.infrastructure.acl:with-git-process-fns
        ((list :spawn (lambda (cmd args &key output error wait process-group)
                        (declare (ignore cmd output error wait process-group))
                        (push args calls)
                        (make-fake-git-process
                         :output (if (member "rev-parse" args :test #'string=)
                                     (format nil "main~%")
                                     (format nil " M file.lisp~%"))
                         :exit-code 0))
               :output (lambda (proc)
                         (make-string-input-stream (fake-git-process-output proc)))
               :exit-code #'fake-git-process-exit-code))
      (multiple-value-bind (branch dirty-p) (nshell.infrastructure.acl:get-git-status "/repo/")
        (is (string= "main" branch))
        (is (not (null dirty-p))))
      (multiple-value-bind (branch dirty-p) (nshell.infrastructure.acl:get-git-status "/repo/")
        (is (string= "main" branch))
        (is (not (null dirty-p)))))
    (is (= 2 (length calls)))))
