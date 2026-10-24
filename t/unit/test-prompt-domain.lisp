(in-package #:nshell/test)

(describe "prompt-domain-tests"
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

  (it "git-segment-resolves-branch-and-dirty-marker-on-the-left-prompt"
    "A dirty repository's branch resolves through the domain git status resolver
onto the left prompt, after the path."
    (let ((nshell.domain.prompting:*git-status-resolver*
            (lambda (dir)
              (expect "/repo/" :to-equal dir)
              (values "main" t))))
      (let* ((pm (nshell.domain.prompting:make-prompt-model
                  :hostname "h"
                  :cwd "/repo"
                  :directory "/repo/"))
             (result (nshell.domain.prompting:render-prompt-model pm))
             (git (find-if (lambda (seg)
                            (member (nshell.domain.prompting:prompt-segment-kind seg)
                                    '(:git :git-dirty)))
                           result)))
        (expect "main*" :to-equal (nshell.domain.prompting:prompt-segment-text git))
        (expect :git-dirty :to-be (nshell.domain.prompting:prompt-segment-kind git)))))

  (it "default-right-prompt-includes-only-a-nonzero-exit-code"
    "Git status no longer appears on the right prompt; it moved to the left."
    (let ((nshell.domain.prompting:*git-status-resolver*
            (lambda (dir)
              (declare (ignore dir))
              (values "feature" nil)))
          (nshell.domain.prompting:*prompt-time-resolver*
            (lambda () nil)))
      (let* ((pm (nshell.domain.prompting:make-prompt-model
                  :hostname "h" :cwd "/repo/" :directory "/repo/" :exit-code 2))
             (result (nshell.domain.prompting:render-right-prompt-model pm)))
        (expect 1 :to-equal (length result))
        (expect "[2]" :to-equal (nshell.domain.prompting:prompt-segment-text (first result)))
        (expect :exit-error :to-be (nshell.domain.prompting:prompt-segment-kind (first result))))))

  (it "default-right-prompt-appends-duration-and-time-after-the-exit-code"
    "Default right prompt includes duration (shown from one second up) and time
after a non-zero exit code; git no longer appears here."
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
                  :duration-ms 1234))
             (result (nshell.domain.prompting:render-right-prompt-model pm)))
        (expect 5 :to-equal (length result))
        (expect "[2]" :to-equal (nshell.domain.prompting:prompt-segment-text (first result)))
        (expect :exit-error :to-be (nshell.domain.prompting:prompt-segment-kind (first result)))
        (expect " " :to-equal (nshell.domain.prompting:prompt-segment-text (second result)))
        (expect :literal :to-be (nshell.domain.prompting:prompt-segment-kind (second result)))
        (expect "1.2s" :to-equal (nshell.domain.prompting:prompt-segment-text (third result)))
        (expect :duration :to-be (nshell.domain.prompting:prompt-segment-kind (third result)))
        (expect " " :to-equal (nshell.domain.prompting:prompt-segment-text (fourth result)))
        (expect :literal :to-be (nshell.domain.prompting:prompt-segment-kind (fourth result)))
        (expect "12:34" :to-equal (nshell.domain.prompting:prompt-segment-text (fifth result)))
        (expect :time :to-be (nshell.domain.prompting:prompt-segment-kind (fifth result))))))

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

(describe "fr-004-prompt-explain-marker-contracts"
  (it "marks-only-a-nonzero-exit-and-clears-after-a-success"
    (let ((nshell.domain.prompting:*git-status-resolver*
            (lambda (directory)
              (declare (ignore directory))
              (values nil nil)))
          (nshell.domain.prompting:*prompt-time-resolver*
            (lambda () nil)))
      (let* ((failed
               (nshell.domain.prompting:make-prompt-model
                :hostname "h" :cwd "/repo/" :exit-code 7))
             (succeeded
               (nshell.domain.prompting:make-prompt-model
                :hostname "h" :cwd "/repo/" :exit-code 0))
             (failed-with-explain
               (nshell.domain.prompting:render-right-prompt-model
                failed :failure-explain-p t))
             (failed-without-explain
               (nshell.domain.prompting:render-right-prompt-model
                failed :failure-explain-p nil))
             (succeeded-after-failure
               (nshell.domain.prompting:render-right-prompt-model
                succeeded :failure-explain-p t)))
        (expect "[7 · ?]"
                :to-equal
                (nshell.domain.prompting:prompt-segment-text
                 (first failed-with-explain)))
        (expect "[7]"
                :to-equal
                (nshell.domain.prompting:prompt-segment-text
                 (first failed-without-explain)))
        (expect nil :to-be succeeded-after-failure)))))

(describe "git-status-edge-tests"
  (it "normalizes-git-output-at-the-boundary"
    "Git command output loses trailing line-oriented whitespace before classification."
    (expect "main"
            :to-equal
            (nshell.infrastructure.acl::%trim-newline (format nil "main~%~% "))))
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
  (it "prompt-git-status-returns-before-slow-worker-completes"
    "The lookup returns while a fake Git worker waits behind a semaphore barrier."
    (let* ((worker-started (sb-thread:make-semaphore :count 0))
           (release-worker (sb-thread:make-semaphore :count 0))
           (worker-finished (sb-thread:make-semaphore :count 0))
           (lookup-returned (sb-thread:make-semaphore :count 0))
           (worker-thread nil)
           (lookup-thread nil)
           (lookup-result nil)
           (runner
             (lambda (dir args)
               (declare (ignore dir))
               (if (member "rev-parse" args :test (function string=))
                   (progn
                     (sb-thread:signal-semaphore worker-started)
                     (unless (sb-thread:wait-on-semaphore release-worker :timeout 3)
                       (error "Git worker test barrier was not released"))
                     (values (format nil "main~%") 0))
                   (progn
                     (sb-thread:signal-semaphore worker-finished)
                     (values "" 0))))))
      (nshell.infrastructure.acl:clear-git-status-cache)
      (unwind-protect
           (progn
             (setf lookup-thread
                   (sb-thread:make-thread
                    (lambda ()
                      (let ((nshell.infrastructure.acl::*git-runner* runner))
                        (progv (list (quote nshell.infrastructure.acl::*git-status-worker-launcher*))
                            (list (lambda (worker)
                                    (setf worker-thread
                                          (sb-thread:make-thread
                                           worker
                                           :name "test git status worker"))))
                          (setf lookup-result
                                (multiple-value-list
                                 (nshell.infrastructure.acl:get-git-status
                                  "/async-prompt/")))
                          (sb-thread:signal-semaphore lookup-returned))))
                    :name "test git status lookup"))
             (expect (sb-thread:wait-on-semaphore worker-started :timeout 2)
                     :to-be-truthy)
             (expect (sb-thread:wait-on-semaphore lookup-returned :timeout 1.0)
                     :to-be-truthy)
             (expect (list nil nil nil) :to-equal lookup-result)
             (expect (sb-thread:wait-on-semaphore worker-finished :timeout 1.0)
                     :to-be-falsy)
             (sb-thread:signal-semaphore release-worker)
             (expect (sb-thread:wait-on-semaphore worker-finished :timeout 2)
                     :to-be-truthy)
             (sb-thread:join-thread lookup-thread)
             (when worker-thread
               (sb-thread:join-thread worker-thread))
             (setf worker-thread nil)
             (setf lookup-thread nil)
             (multiple-value-bind (branch dirty-p ready-p)
                 (nshell.infrastructure.acl:get-git-status "/async-prompt/")
               (expect "main" :to-equal branch)
               (expect dirty-p :to-be-falsy)
               (expect ready-p :to-be-truthy)))
        (sb-thread:signal-semaphore release-worker)
        (when lookup-thread
          (sb-thread:join-thread lookup-thread))
        (when worker-thread
          (sb-thread:join-thread worker-thread))
        (nshell.infrastructure.acl:clear-git-status-cache))))
  (it "cleared-cache-rejects-stale-worker-publication"
    "A worker started before cache clear cannot replace a post-clear result."
    (let* ((workers nil)
           (old-worker-started (sb-thread:make-semaphore :count 0))
           (release-old-worker (sb-thread:make-semaphore :count 0))
           (old-worker-finished (sb-thread:make-semaphore :count 0))
           (old-thread nil)
           (launcher (lambda (worker) (push worker workers)))
           (old-runner
             (lambda (dir args)
               (declare (ignore dir))
               (if (member "rev-parse" args :test (function string=))
                   (progn
                     (sb-thread:signal-semaphore old-worker-started)
                     (unless (sb-thread:wait-on-semaphore release-old-worker :timeout 3)
                       (error "Stale Git worker test barrier was not released"))
                     (values (format nil "old~%") 0))
                   (progn
                     (sb-thread:signal-semaphore old-worker-finished)
                     (values (format nil " M old.lisp~%") 0)))))
           (new-runner
             (lambda (dir args)
               (declare (ignore dir))
               (values (if (member "rev-parse" args :test (function string=))
                           (format nil "new~%")
                           (format nil " M new.lisp~%"))
                       0))))
      (nshell.infrastructure.acl:clear-git-status-cache)
      (unwind-protect
           (progn
             (let ((nshell.infrastructure.acl::*git-runner* old-runner)
                   (nshell.infrastructure.acl::*git-status-worker-launcher* launcher))
               (expect (list nil nil nil)
                       :to-equal
                       (multiple-value-list
                        (nshell.infrastructure.acl:get-git-status "/stale-worker/"))))
             (setf old-thread
                   (sb-thread:make-thread (pop workers)
                                          :name "test stale Git status worker"))
             (expect (sb-thread:wait-on-semaphore old-worker-started :timeout 2)
                     :to-be-truthy)
             (nshell.infrastructure.acl:clear-git-status-cache)
             (let ((nshell.infrastructure.acl::*git-runner* new-runner)
                   (nshell.infrastructure.acl::*git-status-worker-launcher* launcher))
               (expect (list nil nil nil)
                       :to-equal
                       (multiple-value-list
                        (nshell.infrastructure.acl:get-git-status "/stale-worker/"))))
             (funcall (pop workers))
             (multiple-value-bind (branch dirty-p ready-p)
                 (nshell.infrastructure.acl:get-git-status "/stale-worker/")
               (expect "new" :to-equal branch)
               (expect ready-p :to-be-truthy)
               (expect dirty-p :to-be-truthy))
             (sb-thread:signal-semaphore release-old-worker)
             (expect (sb-thread:wait-on-semaphore old-worker-finished :timeout 2)
                     :to-be-truthy)
             (sb-thread:join-thread old-thread)
             (setf old-thread nil)
             (multiple-value-bind (branch dirty-p ready-p)
                 (nshell.infrastructure.acl:get-git-status "/stale-worker/")
               (expect "new" :to-equal branch)
               (expect ready-p :to-be-truthy)
               (expect dirty-p :to-be-truthy)))
        (sb-thread:signal-semaphore release-old-worker)
        (when old-thread
          (sb-thread:join-thread old-thread))
        (nshell.infrastructure.acl:clear-git-status-cache))))
  (it "worker-errors-publish-failed-status"
    "An unexpected Git runner error is cached as a failed query, not as pending."
    (let* ((worker nil)
           (calls 0)
           (runner
             (lambda (dir args)
               (declare (ignore dir args))
               (incf calls)
               (error "Fake Git runner failure"))))
      (nshell.infrastructure.acl:clear-git-status-cache)
      (unwind-protect
           (progn
             (let ((nshell.infrastructure.acl::*git-runner* runner)
                   (nshell.infrastructure.acl::*git-status-worker-launcher*
                     (lambda (scheduled-worker)
                       (setf worker scheduled-worker))))
               (expect (list nil nil nil)
                       :to-equal
                       (multiple-value-list
                        (nshell.infrastructure.acl:get-git-status "/worker-error/"))))
             (expect worker :to-be-truthy)
             (funcall worker)
             (expect 1 :to-equal calls)
             (multiple-value-bind (entry present-p)
                 (gethash "/worker-error/"
                          nshell.infrastructure.acl::*git-status-cache*)
               (expect present-p :to-be-truthy)
               (expect (list nil nil t)
        :to-equal
        (multiple-value-list
         (nshell.infrastructure.acl:get-git-status "/worker-error/")))
               (expect (list nil nil) :to-equal entry)))
        (nshell.infrastructure.acl:clear-git-status-cache))))
  (it "git-status-worker-drain-waits-for-worker-unwind"
    "The drain helper joins a tracked Git worker before returning."
    (let* ((worker-started (sb-thread:make-semaphore :count 0))
           (release-worker (sb-thread:make-semaphore :count 0))
           (worker-finished (sb-thread:make-semaphore :count 0))
           (drain-started (sb-thread:make-semaphore :count 0))
           (drain-finished (sb-thread:make-semaphore :count 0))
           (worker-thread nil)
           (drain-thread nil))
      (unwind-protect
           (progn
             (setf worker-thread
                   (nshell.infrastructure.acl::%start-git-status-worker
                    (lambda ()
                      (sb-thread:signal-semaphore worker-started)
                      (unless (sb-thread:wait-on-semaphore release-worker :timeout 3)
                        (error "Git worker drain test barrier was not released"))
                      (sb-thread:signal-semaphore worker-finished))))
             (expect worker-thread :to-be-truthy)
             (expect (sb-thread:wait-on-semaphore worker-started :timeout 2)
                     :to-be-truthy)
             (setf drain-thread
                   (sb-thread:make-thread
                    (lambda ()
                      (sb-thread:signal-semaphore drain-started)
                      (nshell.infrastructure.acl::%drain-git-status-workers)
                      (sb-thread:signal-semaphore drain-finished))
                    :name "test Git status worker drain"))
             (expect (sb-thread:wait-on-semaphore drain-started :timeout 2)
                     :to-be-truthy)
             (expect (sb-thread:wait-on-semaphore drain-finished :timeout 1.0)
                     :to-be-falsy)
             (sb-thread:signal-semaphore release-worker)
             (expect (sb-thread:wait-on-semaphore worker-finished :timeout 2)
                     :to-be-truthy)
             (expect (sb-thread:wait-on-semaphore drain-finished :timeout 2)
                     :to-be-truthy)
             (sb-thread:join-thread worker-thread)
             (setf worker-thread nil)
             (sb-thread:join-thread drain-thread)
             (setf drain-thread nil))
        (sb-thread:signal-semaphore release-worker)
        (when drain-thread
          (sb-thread:join-thread drain-thread))
        (when worker-thread
          (sb-thread:join-thread worker-thread))
        (sb-thread:with-mutex (nshell.infrastructure.acl::*git-status-worker-lock*)
          (setf nshell.infrastructure.acl::*git-status-worker-threads* nil
                nshell.infrastructure.acl::*git-status-workers-draining-p* nil)))))
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
        (expect (plusp code) :to-be-truthy)))))

(describe "prompt-failure-explain-segment-tests"
  (it "shows-the-explain-affordance-only-for-an-active-failure"
    (let ((nshell.domain.prompting:*git-status-resolver*
            (lambda (directory)
              (declare (ignore directory))
              (values nil nil))))
      (let ((pm (nshell.domain.prompting:make-prompt-model
                 :hostname "h" :cwd "/repo/" :exit-code 1)))
        (expect "[1 · ?]"
                :to-equal
                (nshell.domain.prompting:prompt-segment-text
                 (first
                  (nshell.domain.prompting:render-right-prompt-model
                   pm :failure-explain-p t))))
        (expect "[1]"
                :to-equal
                (nshell.domain.prompting:prompt-segment-text
                 (first
                  (nshell.domain.prompting:render-right-prompt-model
                   pm :failure-explain-p nil))))))))
