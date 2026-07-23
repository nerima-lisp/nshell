(in-package #:nshell/test)

(describe "prompt-tests"
  (it "prompt-constructors-and-accessors-are-public"
    (let ((pm (nshell.domain.prompting:make-prompt-model
               :hostname "h"
               :cwd "/repo/"
               :segments (list (nshell.domain.prompting:make-prompt-segment "h" :host))))
          (segment (nshell.domain.prompting:make-prompt-segment "main" :git)))
      (expect "h" :to-equal (nshell.domain.prompting:prompt-model-hostname pm))
      (expect "/repo/" :to-equal (nshell.domain.prompting:prompt-model-cwd pm))
      (expect (nshell.domain.prompting:prompt-model-directory pm) :to-be-null)
      (let ((rendered (first (nshell.domain.prompting:render-prompt-model pm))))
        (expect "h" :to-equal (nshell.domain.prompting:prompt-segment-text rendered))
        (expect :host :to-be (nshell.domain.prompting:prompt-segment-kind rendered)))
      (expect "main" :to-equal (nshell.domain.prompting:prompt-segment-text segment))
      (expect :git :to-be (nshell.domain.prompting:prompt-segment-kind segment))
      (expect (fboundp 'nshell.domain.prompting:make-prompt-model) :to-be-truthy)
      (expect (fboundp 'nshell.domain.prompting:make-prompt-segment) :to-be-truthy)))

  (it "prompt-model-factory-owns-input-segment-lists"
    "Prompt model construction detaches list identity from caller-owned collections."
    (let* ((caller-segments
             (list (nshell.domain.prompting:make-prompt-segment "h" :host)))
           (caller-right-segments
             (list (nshell.domain.prompting:make-prompt-segment "" :git)))
           (pm (nshell.domain.prompting:make-prompt-model
                :hostname "h"
                :cwd "/repo/"
                :segments caller-segments
                :right-segments caller-right-segments)))
      (setf (first caller-segments)
            (nshell.domain.prompting:make-prompt-segment "changed" :path))
      (setf (first caller-right-segments)
            (nshell.domain.prompting:make-prompt-segment "changed" :literal))
      (expect "h" :to-equal (nshell.domain.prompting:prompt-segment-text
                    (first (nshell.domain.prompting:prompt-model-segments pm))))
      (expect :git :to-be (nshell.domain.prompting:prompt-segment-kind
               (first (nshell.domain.prompting:prompt-model-right-segments pm))))
      (let ((returned (nshell.domain.prompting:prompt-model-segments pm)))
        (setf (first returned)
              (nshell.domain.prompting:make-prompt-segment "returned" :path))
        (expect "h" :to-equal (nshell.domain.prompting:prompt-segment-text
                      (first (nshell.domain.prompting:prompt-model-segments pm)))))))

  (it "prompt-construction-boundary-hides-raw-copy-and-validates-values"
    "Prompt domain values are created through semantic factories, not generated copy APIs."
    (expect (fboundp 'nshell.domain.prompting::copy-prompt-model) :to-be-falsy)
    (expect (fboundp 'nshell.domain.prompting::copy-prompt-segment) :to-be-falsy)
    (expect (lambda () (nshell.domain.prompting:make-prompt-model :hostname :not-a-string)) :to-throw 'error)
    (expect (lambda () (nshell.domain.prompting:make-prompt-model :segments :not-a-list)) :to-throw 'error)
    (expect (lambda () (nshell.domain.prompting:make-prompt-segment 42 :host)) :to-throw 'error)
    (expect (lambda () (nshell.domain.prompting:make-prompt-segment "x" 'host)) :to-throw 'error))

  (it "git-segment-resolves-branch-and-dirty-marker"
    "A :git segment is resolved through the domain git status resolver."
    (let ((nshell.domain.prompting:*git-status-resolver*
            (lambda (dir)
              (expect "/repo/" :to-equal dir)
              (values "main" t))))
      (let* ((pm (nshell.domain.prompting:make-prompt-model
                  :hostname "h"
                  :cwd "/repo/"
                  :directory "/repo/"
                  :right-segments (list (nshell.domain.prompting:make-prompt-segment "" :git))))
             (result (nshell.domain.prompting:render-right-prompt-model pm)))
        (expect "main*" :to-equal (nshell.domain.prompting:prompt-segment-text (first result)))
        (expect :git :to-be (nshell.domain.prompting:prompt-segment-kind (first result))))))

  (it "default-right-prompt-includes-git-and-exit-code"
    "Default right prompt displays git status and non-zero exit code."
    (let ((nshell.domain.prompting:*git-status-resolver*
            (lambda (dir)
              (declare (ignore dir))
              (values "feature" nil))))
      (let* ((pm (nshell.domain.prompting:make-prompt-model
                  :hostname "h" :cwd "/repo/" :directory "/repo/" :exit-code 2))
             (result (nshell.domain.prompting:render-right-prompt-model pm)))
        (expect "feature" :to-equal (nshell.domain.prompting:prompt-segment-text (first result)))
        (expect :git :to-be (nshell.domain.prompting:prompt-segment-kind (first result)))
        (expect " " :to-equal (nshell.domain.prompting:prompt-segment-text (second result)))
        (expect :literal :to-be (nshell.domain.prompting:prompt-segment-kind (second result)))
        (expect "[2]" :to-equal (nshell.domain.prompting:prompt-segment-text (third result)))
        (expect :exit-error :to-be (nshell.domain.prompting:prompt-segment-kind (third result))))))

  (it "default-right-prompt-appends-duration-and-time"
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
        (expect 7 :to-equal (length result))
        (expect "feature" :to-equal (nshell.domain.prompting:prompt-segment-text (first result)))
        (expect :git :to-be (nshell.domain.prompting:prompt-segment-kind (first result)))
        (expect " " :to-equal (nshell.domain.prompting:prompt-segment-text (second result)))
        (expect :literal :to-be (nshell.domain.prompting:prompt-segment-kind (second result)))
        (expect "[2]" :to-equal (nshell.domain.prompting:prompt-segment-text (third result)))
        (expect :exit-error :to-be (nshell.domain.prompting:prompt-segment-kind (third result)))
        (expect " " :to-equal (nshell.domain.prompting:prompt-segment-text (fourth result)))
        (expect :literal :to-be (nshell.domain.prompting:prompt-segment-kind (fourth result)))
        (expect "123ms" :to-equal (nshell.domain.prompting:prompt-segment-text (fifth result)))
        (expect :duration :to-be (nshell.domain.prompting:prompt-segment-kind (fifth result)))
        (expect " " :to-equal (nshell.domain.prompting:prompt-segment-text (sixth result)))
        (expect :literal :to-be (nshell.domain.prompting:prompt-segment-kind (sixth result)))
        (expect "12:34" :to-equal (nshell.domain.prompting:prompt-segment-text (seventh result)))
        (expect :time :to-be (nshell.domain.prompting:prompt-segment-kind (seventh result))))))

  (it "git-status-uses-process-adapter-and-cache"
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
          (expect "main" :to-equal branch)
          (expect (null dirty-p) :to-be-falsy))
        (multiple-value-bind (branch dirty-p) (nshell.infrastructure.acl:get-git-status "/repo/")
          (expect "main" :to-equal branch)
          (expect (null dirty-p) :to-be-falsy)))
      (expect 2 :to-equal (length calls)))))
