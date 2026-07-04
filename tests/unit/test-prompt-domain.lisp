(in-package #:nshell/test)

(in-suite prompt-tests)

(test prompt-constructors-and-accessors-are-public
  (let ((pm (nshell.domain.prompting:make-prompt-model
             :hostname "h"
             :cwd "/repo/"
             :segments (list (nshell.domain.prompting:make-prompt-segment "h" :host))))
        (segment (nshell.domain.prompting:make-prompt-segment "main" :git)))
    (is (string= "h" (nshell.domain.prompting:prompt-model-hostname pm)))
    (is (string= "/repo/" (nshell.domain.prompting:prompt-model-cwd pm)))
    (is (null (nshell.domain.prompting:prompt-model-directory pm)))
    (let ((rendered (first (nshell.domain.prompting:render-prompt-model pm))))
      (is (string= "h" (nshell.domain.prompting:prompt-segment-text rendered)))
      (is (eq :host (nshell.domain.prompting:prompt-segment-kind rendered))))
    (is (string= "main" (nshell.domain.prompting:prompt-segment-text segment)))
    (is (eq :git (nshell.domain.prompting:prompt-segment-kind segment)))
    (is (fboundp 'nshell.domain.prompting:make-prompt-model))
    (is (fboundp 'nshell.domain.prompting:make-prompt-segment))))

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
      (is (string= "main*" (nshell.domain.prompting:prompt-segment-text (first result))))
      (is (eq :git (nshell.domain.prompting:prompt-segment-kind (first result)))))))

(test default-right-prompt-includes-git-and-exit-code
  "Default right prompt displays git status and non-zero exit code."
  (let ((nshell.domain.prompting:*git-status-resolver*
          (lambda (dir)
            (declare (ignore dir))
            (values "feature" nil))))
    (let* ((pm (nshell.domain.prompting:make-prompt-model
                :hostname "h" :cwd "/repo/" :directory "/repo/" :exit-code 2))
           (result (nshell.domain.prompting:render-right-prompt-model pm)))
      (is (string= "feature" (nshell.domain.prompting:prompt-segment-text (first result))))
      (is (eq :git (nshell.domain.prompting:prompt-segment-kind (first result))))
      (is (string= " " (nshell.domain.prompting:prompt-segment-text (second result))))
      (is (eq :literal (nshell.domain.prompting:prompt-segment-kind (second result))))
      (is (string= "[2]" (nshell.domain.prompting:prompt-segment-text (third result))))
      (is (eq :exit-error (nshell.domain.prompting:prompt-segment-kind (third result)))))))

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
      (is (string= "feature" (nshell.domain.prompting:prompt-segment-text (first result))))
      (is (eq :git (nshell.domain.prompting:prompt-segment-kind (first result))))
      (is (string= " " (nshell.domain.prompting:prompt-segment-text (second result))))
      (is (eq :literal (nshell.domain.prompting:prompt-segment-kind (second result))))
      (is (string= "[2]" (nshell.domain.prompting:prompt-segment-text (third result))))
      (is (eq :exit-error (nshell.domain.prompting:prompt-segment-kind (third result))))
      (is (string= " " (nshell.domain.prompting:prompt-segment-text (fourth result))))
      (is (eq :literal (nshell.domain.prompting:prompt-segment-kind (fourth result))))
      (is (string= "123ms" (nshell.domain.prompting:prompt-segment-text (fifth result))))
      (is (eq :duration (nshell.domain.prompting:prompt-segment-kind (fifth result))))
      (is (string= " " (nshell.domain.prompting:prompt-segment-text (sixth result))))
      (is (eq :literal (nshell.domain.prompting:prompt-segment-kind (sixth result))))
      (is (string= "12:34" (nshell.domain.prompting:prompt-segment-text (seventh result))))
      (is (eq :time (nshell.domain.prompting:prompt-segment-kind (seventh result)))))))

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
