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

  (it "git-status-uses-runner-and-cache"
    "Git status is executed through the injected runner and cached per directory."
    (let ((calls nil))
      (nshell.infrastructure.acl:clear-git-status-cache)
      (nshell.infrastructure.acl:with-git-runner
          ((lambda (dir args)
             (declare (ignore dir))
             (push args calls)
             (values (if (member "rev-parse" args :test #'string=)
                         (format nil "main~%")
                         (format nil " M file.lisp~%"))
                     0)))
        (multiple-value-bind (branch dirty-p) (nshell.infrastructure.acl:get-git-status "/repo/")
          (expect "main" :to-equal branch)
          (expect (null dirty-p) :to-be-falsy))
        (multiple-value-bind (branch dirty-p) (nshell.infrastructure.acl:get-git-status "/repo/")
          (expect "main" :to-equal branch)
          (expect (null dirty-p) :to-be-falsy)))
      (expect 2 :to-equal (length calls)))))
(describe "git-status-edge-tests"
  (it "treats-detached-head-as-no-branch"
    (let ((calls nil))
      (nshell.infrastructure.acl:clear-git-status-cache)
      (nshell.infrastructure.acl:with-git-runner
          ((lambda (dir args)
             (declare (ignore dir))
             (push args calls)
             (values (if (member "rev-parse" args :test (lambda (value item) (string= value item)))
                         (format nil "HEAD~%")
                         "")
                     0)))
        (multiple-value-bind (branch dirty-p)
            (nshell.infrastructure.acl:get-git-status "/detached/")
          (expect branch :to-be-null)
          (expect dirty-p :to-be-falsy)))
      (expect 1 :to-equal (length calls))))
  (it "clearing-cache-forces-a-fresh-query"
    (let ((calls 0))
      (nshell.infrastructure.acl:clear-git-status-cache)
      (nshell.infrastructure.acl:with-git-runner
          ((lambda (dir args)
             (declare (ignore dir args))
             (incf calls)
             (values (format nil "main~%") 0)))
        (nshell.infrastructure.acl:get-git-status "/cache-reset/")
        (nshell.infrastructure.acl:get-git-status "/cache-reset/")
        (nshell.infrastructure.acl:clear-git-status-cache)
        (nshell.infrastructure.acl:get-git-status "/cache-reset/"))
      (expect 4 :to-equal calls)))
  (it "rejects-empty-and-failed-branch-results"
    "A missing or failed branch query does not classify the directory as a repository."
    (dolist (case (list (list "/empty-branch/" "" 0)
                        (list "/failed-branch/" "main" 1)))
      (destructuring-bind (dir output code) case
        (let ((calls 0))
          (nshell.infrastructure.acl:clear-git-status-cache)
          (nshell.infrastructure.acl:with-git-runner
              ((lambda (runner-dir args)
                 (declare (ignore runner-dir))
                 (incf calls)
                 (if (member "rev-parse" args
                             :test (lambda (value item) (string= value item)))
                     (values output code)
                     (values (format nil " M file.lisp~%") 0))))
            (multiple-value-bind (branch dirty-p)
                (nshell.infrastructure.acl:get-git-status dir)
              (expect branch :to-be-null)
              (expect dirty-p :to-be-falsy)))
          (expect 1 :to-equal calls)))))
  (it "classifies-clean-git-status"
    "A successful empty porcelain response is a clean repository."
    (let ((calls 0))
      (nshell.infrastructure.acl:clear-git-status-cache)
      (nshell.infrastructure.acl:with-git-runner
          ((lambda (runner-dir args)
             (declare (ignore runner-dir))
             (incf calls)
             (if (member "rev-parse" args
                         :test (lambda (value item) (string= value item)))
                 (values (format nil "main~%") 0)
                 (values "" 0))))
        (multiple-value-bind (branch dirty-p)
            (nshell.infrastructure.acl:get-git-status "/clean-status/")
          (expect "main" :to-equal branch)
          (expect dirty-p :to-be-falsy)))
      (expect 2 :to-equal calls)))
  (it "classifies-failed-git-status"
    "A failed porcelain response does not report a dirty repository."
    (let ((calls 0))
      (nshell.infrastructure.acl:clear-git-status-cache)
      (nshell.infrastructure.acl:with-git-runner
          ((lambda (runner-dir args)
             (declare (ignore runner-dir))
             (incf calls)
             (if (member "rev-parse" args
                         :test (lambda (value item) (string= value item)))
                 (values (format nil "main~%") 0)
                 (values "status unavailable" 1))))
        (multiple-value-bind (branch dirty-p)
            (nshell.infrastructure.acl:get-git-status "/failed-status/")
          (expect "main" :to-equal branch)
          (expect dirty-p :to-be-falsy)))
      (expect 2 :to-equal calls)))
  (it "git-runner-converts-invalid-repository-to-an-empty-result"
    "A prompt probe must remain non-blocking for an invalid repository."
    (let ((nshell.infrastructure.acl::*git-runner* nil))
      (multiple-value-bind (output code)
          (nshell.infrastructure.acl::%run-git
           "/path/that/does/not/exist/"
           '("rev-parse" "--abbrev-ref" "HEAD"))
        (expect "" :to-equal output)
        (expect 128 :to-equal code)))))
