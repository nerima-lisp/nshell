(in-package #:nshell/test)

(defun %wait-for-suggestion-worker-result ()
  (loop repeat 500
        for result = (nshell.presentation::%take-suggestion-worker-result)
        when result
          return result
        do (sleep 0.002)
        finally (return nil)))

(describe "repl-suggestion-worker"
  (it "prioritizes buffered input over idle events"
    (let ((idle-calls 0)
          (event nil))
      (let ((*standard-input* (make-string-input-stream "x")))
        (setf event
              (nshell.infrastructure.terminal:read-key-event
               :interrupt-predicate (constantly nil)
               :idle-predicate
               (lambda ()
                 (incf idle-calls)
                 (nshell.domain.input:make-key-event :ctrl-c)))))
      (expect :char :to-be (nshell.domain.input:key-event-type event))
      (expect #\x :to-be (nshell.domain.input:key-event-char event))
      (expect 0 :to-equal idle-calls))
    (let ((idle-calls 0)
          (event nil))
      (let ((*standard-input* (make-string-input-stream "")))
        (setf event
              (nshell.infrastructure.terminal:read-key-event
               :interrupt-predicate (constantly nil)
               :idle-predicate
               (lambda ()
                 (incf idle-calls)
                 (nshell.domain.input:make-key-event :ctrl-c)))))
      (expect :ctrl-c :to-be (nshell.domain.input:key-event-type event))
      (expect 1 :to-equal idle-calls)))

  (it "runs suggestion work off-thread and coalesces to the newest input"
    (with-repl-test-state
      (let ((nshell.presentation::*suggestion-worker-state* nil)
            (nshell.presentation::*suggestion-history-source* nil)
            (nshell.presentation::*suggestion-history-snapshot* nil))
        (let* ((old-started (sb-thread:make-semaphore :count 0))
               (old-release (sb-thread:make-semaphore :count 0))
               (new-started (sb-thread:make-semaphore :count 0))
               (new-release (sb-thread:make-semaphore :count 0))
               (watchdog
                 (sb-thread:make-thread
                  (lambda ()
                    (sleep 0.2)
                    (sb-thread:signal-semaphore old-started)
                    (sb-thread:signal-semaphore old-release)
                    (sb-thread:signal-semaphore new-started)
                    (sb-thread:signal-semaphore new-release))))
               (caller-thread sb-thread:*current-thread*)
               (inline-p nil))
          (unwind-protect
               (with-temporary-functions
                   (('nshell.presentation:compute-suggestion
                     (lambda (history input &rest arguments)
                       (declare (ignore history arguments))
                       (when (eq sb-thread:*current-thread* caller-thread)
                         (setf inline-p t))
                       (if (string= input "old")
                           (progn
                             (sb-thread:signal-semaphore old-started)
                             (unless (eq sb-thread:*current-thread* caller-thread)
                               (sb-thread:wait-on-semaphore old-release))
                             " stale")
                           (progn
                             (sb-thread:signal-semaphore new-started)
                             (unless (eq sb-thread:*current-thread* caller-thread)
                               (sb-thread:wait-on-semaphore new-release))
                             " fresh")))))
                 (setf nshell.presentation::*input-state*
                       (nshell.presentation:make-input-state
                        :buffer "old" :cursor-pos 3))
                 (nshell.presentation::%schedule-current-input-state-suggestion)
                 (expect nil :to-equal inline-p)
                 (sb-thread:wait-on-semaphore old-started)
                 (setf nshell.presentation::*input-state*
                       (nshell.presentation:make-input-state
                        :buffer "new" :cursor-pos 3))
                 (let ((generation
                         (nshell.presentation::%schedule-current-input-state-suggestion)))
                   (sb-thread:signal-semaphore old-release)
                   (sb-thread:wait-on-semaphore new-started)
                   (expect nil :to-equal
                           (nshell.presentation::%take-suggestion-worker-result))
                   (sb-thread:signal-semaphore new-release)
                   (let ((result (%wait-for-suggestion-worker-result)))
                     (expect result :to-be-truthy)
                     (when result
                       (expect generation :to-equal
                               (nshell.presentation::%suggestion-worker-result-generation
                                result))
                       (expect "new" :to-equal
                               (nshell.presentation::%suggestion-worker-result-text
                                result))
                       (expect " fresh" :to-equal
                               (nshell.presentation::%suggestion-worker-result-suggestion
                                result))))))
            (sb-thread:signal-semaphore old-release)
            (sb-thread:signal-semaphore new-release)
            (nshell.presentation::%stop-suggestion-worker)
            (sb-thread:join-thread watchdog))))))

  (it "keeps history suggestion text and right-key acceptance"
    (with-repl-test-state
      (let ((nshell.presentation::*suggestion-worker-state* nil)
            (nshell.presentation::*suggestion-history-source* nil)
            (nshell.presentation::*suggestion-history-snapshot* nil))
        (unwind-protect
             (progn
               (history-kit:history-add nshell.presentation::*history* "docker ps")
               (nshell.presentation::%refresh-suggestion-history-snapshot)
               (setf nshell.presentation::*input-state*
                     (nshell.presentation:make-input-state
                      :buffer "docker" :cursor-pos 6))
               (nshell.presentation::%schedule-current-input-state-suggestion)
               (let ((result (%wait-for-suggestion-worker-result)))
                 (expect result :to-be-truthy)
                 (when result
                   (expect " ps" :to-equal
                           (nshell.presentation::%suggestion-worker-result-suggestion
                            result))
                   (expect (nshell.presentation::%current-suggestion-worker-result-p
                            result)
                           :to-be-truthy)
                   (setf (nshell.presentation::input-state-suggestion
                          nshell.presentation::*input-state*)
                         (nshell.presentation::%suggestion-worker-result-suggestion
                          result))
                   (multiple-value-bind (new-state output-event)
                       (nshell.presentation:reduce-input-state
                        nshell.presentation::*input-state*
                        (nshell.domain.input:make-key-event :right))
                     (declare (ignore output-event))
                     (expect "docker ps" :to-equal
                             (nshell.presentation::input-state-buffer new-state))))))
          (nshell.presentation::%stop-suggestion-worker)))))
  (it "accepts a suggestion whose calculation is still running"
    (with-repl-test-state
      (let ((nshell.presentation::*suggestion-worker-state* nil)
            (nshell.presentation::*suggestion-history-source* nil)
            (nshell.presentation::*suggestion-history-snapshot* nil))
        (let* ((started (sb-thread:make-semaphore :count 0))
               (release (sb-thread:make-semaphore :count 0))
               (event (nshell.domain.input:make-key-event :right))
               (watchdog
                 (sb-thread:make-thread
                  (lambda ()
                    (sleep 0.2)
                    (sb-thread:signal-semaphore started)
                    (sb-thread:signal-semaphore release)))))
          (unwind-protect
               (with-temporary-function
                   ((quote nshell.presentation:compute-suggestion)
                    (lambda (history input &rest arguments)
                      (declare (ignore history input arguments))
                      (sb-thread:signal-semaphore started)
                      (sb-thread:wait-on-semaphore release)
                      " ps"))
                 (setf nshell.presentation::*input-state*
                       (nshell.presentation:make-input-state
                        :buffer "docker" :cursor-pos 6))
                 (nshell.presentation::%schedule-current-input-state-suggestion)
                 (sb-thread:wait-on-semaphore started)
                 (expect
                  (nshell.presentation::%suggestion-acceptance-key-event-p event)
                  :to-be-truthy)
                 (nshell.presentation::%await-current-suggestion-before-acceptance)
                 (expect " ps" :to-equal
                         (nshell.presentation::input-state-suggestion
                          nshell.presentation::*input-state*))
                 (multiple-value-bind (new-state output-event)
                     (nshell.presentation:reduce-input-state
                      nshell.presentation::*input-state* event)
                   (declare (ignore output-event))
                   (expect "docker ps" :to-equal
                           (nshell.presentation::input-state-buffer new-state))))
            (sb-thread:signal-semaphore release)
            (nshell.presentation::%stop-suggestion-worker)
            (sb-thread:join-thread watchdog)))))))
