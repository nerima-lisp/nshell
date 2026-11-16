(in-package #:nshell/test)

(defmacro with-isolated-suggestion-worker (&body body)
  `(let ((nshell.presentation::*suggestion-worker-state* nil)
         (nshell.presentation::*suggestion-history-source* nil)
         (nshell.presentation::*suggestion-history-snapshot* nil)
         (nshell.presentation::*suggestion-knowledge-base-snapshot* nil)
         (nshell.presentation::*suggestion-table-snapshots* nil)
         (nshell.presentation::*suggestion-shown-full-text* nil))
     ,@body))

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
                 ;; Only the worker signals the start semaphores, so a timed
                 ;; out wait means the computation never ran.
                 (expect (sb-thread:wait-on-semaphore old-started :timeout 5)
                         :to-be-truthy)
                 (setf nshell.presentation::*input-state*
                       (nshell.presentation:make-input-state
                        :buffer "new" :cursor-pos 3))
                 (let ((generation
                         (nshell.presentation::%schedule-current-input-state-suggestion)))
                   (sb-thread:signal-semaphore old-release)
                   (expect (sb-thread:wait-on-semaphore new-started :timeout 5)
                           :to-be-truthy)
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
            (nshell.presentation::%stop-suggestion-worker))))))

  (it "draws a history suggestion with the key that typed it"
    ;; Typed-ahead keys never reach the idle poll, so a history match must be
    ;; on the input state when the key handler returns, without the worker.
    (with-repl-test-state
      (with-isolated-suggestion-worker
        (unwind-protect
             (progn
               (history-kit:history-add nshell.presentation::*history* "docker ps")
               (setf nshell.presentation::*input-state*
                     (nshell.presentation:make-input-state
                      :buffer "docker" :cursor-pos 6))
               (nshell.presentation::%schedule-current-input-state-suggestion)
               (expect " ps" :to-equal
                       (nshell.presentation::input-state-suggestion
                        nshell.presentation::*input-state*))
               (expect nshell.presentation::*suggestion-worker-state* :to-be-falsy)
               (multiple-value-bind (new-state output-event)
                   (nshell.presentation:reduce-input-state
                    nshell.presentation::*input-state*
                    (nshell.domain.input:make-key-event :right))
                 (declare (ignore output-event))
                 (expect "docker ps" :to-equal
                         (nshell.presentation::input-state-buffer new-state))))
          (nshell.presentation::%stop-suggestion-worker)))))

  (it "accepts a suggestion whose calculation is still running"
    (with-repl-test-state
      (let ((nshell.presentation::*suggestion-worker-state* nil)
            (nshell.presentation::*suggestion-history-source* nil)
            (nshell.presentation::*suggestion-history-snapshot* nil))
        (let* ((started (sb-thread:make-semaphore :count 0))
               (waiting (sb-thread:make-semaphore :count 0))
               (release (sb-thread:make-semaphore :count 0))
               (event (nshell.domain.input:make-key-event :right))
               (caller-thread sb-thread:*current-thread*)
               (pauses 0)
               (original-pause
                 (symbol-function
                  'nshell.presentation::%pause-suggestion-acceptance-wait))
               (nshell.presentation::*suggestion-acceptance-wait-seconds* 5)
               ;; Releases the computation only once the acceptance has found
               ;; the result missing and paused to wait for it. It never
               ;; signals STARTED, which only the worker may do.
               (releaser
                 (sb-thread:make-thread
                  (lambda ()
                    (when (sb-thread:wait-on-semaphore waiting :timeout 5)
                      (sb-thread:signal-semaphore release))))))
          (unwind-protect
               (with-temporary-functions
                   (('nshell.presentation:compute-suggestion
                     (lambda (history input &rest arguments)
                       (declare (ignore history input arguments))
                       (sb-thread:signal-semaphore started)
                       (sb-thread:wait-on-semaphore release)
                       " ps"))
                    ;; Called only in the wait branch: no result yet and the
                    ;; request still running.
                    ('nshell.presentation::%pause-suggestion-acceptance-wait
                     (lambda ()
                       (when (and (eq sb-thread:*current-thread* caller-thread)
                                  (= 1 (incf pauses)))
                         (sb-thread:signal-semaphore waiting))
                       (funcall original-pause))))
                 (setf nshell.presentation::*input-state*
                       (nshell.presentation:make-input-state
                        :buffer "docker" :cursor-pos 6))
                 (nshell.presentation::%schedule-current-input-state-suggestion)
                 (expect (sb-thread:wait-on-semaphore started :timeout 5)
                         :to-be-truthy)
                 (expect
                  (nshell.presentation::%suggestion-acceptance-key-event-p event)
                  :to-be-truthy)
                 (expect (nshell.presentation::%await-current-suggestion-before-acceptance)
                         :to-be-truthy)
                 ;; The acceptance entered the wait branch before the result.
                 (expect (plusp pauses) :to-be-truthy)
                 (expect " ps" :to-equal
                         (nshell.presentation::input-state-suggestion
                          nshell.presentation::*input-state*))
                 (multiple-value-bind (new-state output-event)
                     (nshell.presentation:reduce-input-state
                      nshell.presentation::*input-state* event)
                   (declare (ignore output-event))
                   (expect "docker ps" :to-equal
                           (nshell.presentation::input-state-buffer new-state))))
            (sb-thread:signal-semaphore waiting)
            (sb-thread:signal-semaphore release)
            (nshell.presentation::%stop-suggestion-worker)
            (sb-thread:join-thread releaser :default nil :timeout 5))))))

  (it "computes the suggestion inline when the worker died mid-request"
    (with-repl-test-state
      (with-isolated-suggestion-worker
        (let ((started (sb-thread:make-semaphore :count 0))
              (never (sb-thread:make-semaphore :count 0))
              (caller-thread sb-thread:*current-thread*))
          (unwind-protect
               (with-temporary-function
                   ((quote nshell.presentation:compute-suggestion)
                    (lambda (history input &rest arguments)
                      (declare (ignore history input arguments))
                      (if (eq sb-thread:*current-thread* caller-thread)
                          " sync"
                          (progn
                            (sb-thread:signal-semaphore started)
                            (sb-thread:wait-on-semaphore never :timeout 10)
                            " late"))))
                 (setf nshell.presentation::*input-state*
                       (nshell.presentation:make-input-state
                        :buffer "docker" :cursor-pos 6))
                 (nshell.presentation::%schedule-current-input-state-suggestion)
                 (expect (sb-thread:wait-on-semaphore started :timeout 5)
                         :to-be-truthy)
                 (let ((thread (nshell.presentation::%suggestion-worker-state-thread
                                nshell.presentation::*suggestion-worker-state*)))
                   (sb-thread:terminate-thread thread)
                   (sb-thread:join-thread thread :default nil :timeout 5)
                   (expect (sb-thread:thread-alive-p thread) :to-be-falsy))
                 (let ((started-at (get-internal-real-time)))
                   (expect (nshell.presentation::%await-current-suggestion-before-acceptance)
                           :to-be-truthy)
                   (expect (< (- (get-internal-real-time) started-at)
                              (* 2 internal-time-units-per-second))
                           :to-be-truthy))
                 (expect " sync" :to-equal
                         (nshell.presentation::input-state-suggestion
                          nshell.presentation::*input-state*))
                 (nshell.presentation::%schedule-current-input-state-suggestion)
                 (expect (nshell.presentation::%suggestion-worker-alive-p
                          nshell.presentation::*suggestion-worker-state*)
                         :to-be-truthy))
            (sb-thread:signal-semaphore never 2)
            (nshell.presentation::%stop-suggestion-worker))))))

  (it "stops waiting for a stuck worker at the acceptance deadline"
    (with-repl-test-state
      (with-isolated-suggestion-worker
        (let ((started (sb-thread:make-semaphore :count 0))
              (release (sb-thread:make-semaphore :count 0))
              (nshell.presentation::*suggestion-acceptance-wait-seconds* 0.05))
          (unwind-protect
               (with-temporary-function
                   ((quote nshell.presentation:compute-suggestion)
                    (lambda (history input &rest arguments)
                      (declare (ignore history input arguments))
                      (sb-thread:signal-semaphore started)
                      (sb-thread:wait-on-semaphore release :timeout 10)
                      " late"))
                 (setf nshell.presentation::*input-state*
                       (nshell.presentation:make-input-state
                        :buffer "docker" :cursor-pos 6))
                 (nshell.presentation::%schedule-current-input-state-suggestion)
                 (expect (sb-thread:wait-on-semaphore started :timeout 5)
                         :to-be-truthy)
                 (let ((started-at (get-internal-real-time)))
                   (expect (nshell.presentation::%await-current-suggestion-before-acceptance)
                           :to-be-falsy)
                   (expect (< (- (get-internal-real-time) started-at)
                              (* 2 internal-time-units-per-second))
                           :to-be-truthy))
                 (expect (nshell.presentation::input-state-suggestion
                          nshell.presentation::*input-state*)
                         :to-be-falsy))
            (sb-thread:signal-semaphore release)
            (nshell.presentation::%stop-suggestion-worker))))))

  (it "keeps the shown suggestion while typing along it"
    (with-repl-test-state
      (with-isolated-suggestion-worker
        (unwind-protect
             (with-temporary-function
                 ((quote nshell.presentation:compute-suggestion)
                  (lambda (history input &rest arguments)
                    (declare (ignore history arguments))
                    (cond
                      ((string= input "dock") "er ps")
                      ((string= input "docke") "r ps")
                      (t nil))))
               (setf nshell.presentation::*input-state*
                     (nshell.presentation:make-input-state
                      :buffer "dock" :cursor-pos 4))
               (nshell.presentation::%schedule-current-input-state-suggestion)
               (expect (nshell.presentation::input-state-suggestion
                        nshell.presentation::*input-state*)
                       :to-be-falsy)
               (let ((result (%wait-for-suggestion-worker-result)))
                 (expect result :to-be-truthy)
                 (expect (nshell.presentation::%apply-suggestion-worker-result result)
                         :to-be-truthy))
               (expect "er ps" :to-equal
                       (nshell.presentation::input-state-suggestion
                        nshell.presentation::*input-state*))
               ;; A typed character that follows the suggestion keeps the rest
               ;; of it on screen before the worker answers.
               (setf nshell.presentation::*input-state*
                     (nshell.presentation:make-input-state
                      :buffer "docke" :cursor-pos 5))
               (nshell.presentation::%schedule-current-input-state-suggestion)
               (expect "r ps" :to-equal
                       (nshell.presentation::input-state-suggestion
                        nshell.presentation::*input-state*))
               (let ((result (%wait-for-suggestion-worker-result)))
                 (expect result :to-be-truthy)
                 (expect (nshell.presentation::%apply-suggestion-worker-result result)
                         :to-be-falsy))
               (expect "r ps" :to-equal
                       (nshell.presentation::input-state-suggestion
                        nshell.presentation::*input-state*))
               ;; A character that leaves the suggestion clears it at once.
               (setf nshell.presentation::*input-state*
                     (nshell.presentation:make-input-state
                      :buffer "dockex" :cursor-pos 6))
               (nshell.presentation::%schedule-current-input-state-suggestion)
               (expect (nshell.presentation::input-state-suggestion
                        nshell.presentation::*input-state*)
                       :to-be-falsy)
               ;; An empty answer for a buffer still on the suggestion clears it.
               (setf nshell.presentation::*input-state*
                     (nshell.presentation:make-input-state
                      :buffer "docke" :cursor-pos 5))
               (nshell.presentation::%show-suggestion "r ps")
               (setf nshell.presentation::*input-state*
                     (nshell.presentation:make-input-state
                      :buffer "docker" :cursor-pos 6))
               (nshell.presentation::%schedule-current-input-state-suggestion)
               (expect " ps" :to-equal
                       (nshell.presentation::input-state-suggestion
                        nshell.presentation::*input-state*))
               (let ((result (%wait-for-suggestion-worker-result)))
                 (expect result :to-be-truthy)
                 (expect (nshell.presentation::%apply-suggestion-worker-result result)
                         :to-be-truthy))
               (expect (nshell.presentation::input-state-suggestion
                        nshell.presentation::*input-state*)
                       :to-be-falsy))
          (nshell.presentation::%stop-suggestion-worker)))))

  (it "redraws when an idle poll delivers a current worker result"
    (with-repl-test-state
      (with-isolated-suggestion-worker
        (let* ((state (nshell.presentation::%make-suggestion-worker-state))
               (result (nshell.presentation::%make-suggestion-worker-result
                        :generation 1 :text "docker" :suggestion " ps"))
               (renders 0))
          (setf (nshell.presentation::%suggestion-worker-state-generation state) 1
                nshell.presentation::*suggestion-worker-state* state
                nshell.presentation::*input-state*
                (nshell.presentation:make-input-state
                 :buffer "docker" :cursor-pos 6))
          (with-temporary-functions
              (('nshell.infrastructure.acl:consume-terminal-resize-p
                (lambda () nil))
               ('nshell.infrastructure.terminal:read-key-event
                (lambda (&key interrupt-predicate)
                  (declare (ignore interrupt-predicate))
                  (nshell.domain.input:make-key-event
                   :ignore nil nil (list :suggestion-worker-result result))))
               ('nshell.presentation::render-prompt-cont
                (lambda () (incf renders) nil)))
            (let ((continuation (nshell.presentation::read-key-cont)))
              (expect (functionp continuation) :to-be-truthy)
              (funcall continuation)))
          (expect 1 :to-equal renders)
          (expect " ps" :to-equal
                  (nshell.presentation::input-state-suggestion
                   nshell.presentation::*input-state*))))))

  (it "reuses worker snapshots until their source changes"
    (with-repl-test-state
      (with-isolated-suggestion-worker
        (let* ((kb (nshell.domain.completion:make-empty-knowledge-base))
               (first-kb (nshell.presentation::%snapshot-suggestion-knowledge-base kb)))
          (expect first-kb :to-be
                  (nshell.presentation::%snapshot-suggestion-knowledge-base kb))
          (nshell.domain.completion:kb-add-command kb "suggest-snapshot-test")
          (let ((second-kb (nshell.presentation::%snapshot-suggestion-knowledge-base kb)))
            (expect (eq first-kb second-kb) :to-be-falsy)
            (expect (nshell.domain.completion:kb-command-present-p
                     second-kb "suggest-snapshot-test")
                    :to-be-truthy)))
        (let* ((aliases (make-hash-table :test #'equal))
               (first-table (nshell.presentation::%snapshot-suggestion-table aliases)))
          (expect first-table :to-be
                  (nshell.presentation::%snapshot-suggestion-table aliases))
          (setf (gethash "ll" aliases) "ls -l")
          (let ((second-table (nshell.presentation::%snapshot-suggestion-table aliases)))
            (expect (eq first-table second-table) :to-be-falsy)
            (expect "ls -l" :to-equal (gethash "ll" second-table))
            (setf (gethash "ll" aliases) "ls -la")
            (expect "ls -la" :to-equal
                    (gethash "ll"
                             (nshell.presentation::%snapshot-suggestion-table aliases)))
            (expect "ls -l" :to-equal (gethash "ll" second-table)))))))

  (it "stops a worker blocked in a read within a deadline"
    ;; Opening a FIFO without a writer blocks in open(2), as a GNUmakefile FIFO
    ;; or a hung NFS mount does under make-target completion. The stop runs in
    ;; its own thread with a bounded join, so a regression fails, not hangs.
    (with-repl-test-state
      (with-isolated-suggestion-worker
        (let* ((directory
                 (sb-posix:mkdtemp
                  (namestring
                   (merge-pathnames "nshell-suggest-XXXXXX"
                                    (uiop:temporary-directory)))))
               (fifo (format nil "~a/blocked" directory))
               (started (sb-thread:make-semaphore :count 0))
               (stopper nil))
          (sb-posix:mkfifo fifo #o600)
          (unwind-protect
               (with-temporary-function
                   ((quote nshell.presentation:compute-suggestion)
                    (lambda (history input &rest arguments)
                      (declare (ignore history input arguments))
                      (sb-thread:signal-semaphore started)
                      (with-open-file (stream fifo :element-type '(unsigned-byte 8))
                        (read-byte stream nil nil))
                      " late"))
                 (setf nshell.presentation::*input-state*
                       (nshell.presentation:make-input-state
                        :buffer "make " :cursor-pos 5))
                 (nshell.presentation::%schedule-current-input-state-suggestion)
                 (expect (sb-thread:wait-on-semaphore started :timeout 5)
                         :to-be-truthy)
                 (let ((state nshell.presentation::*suggestion-worker-state*))
                   (setf stopper
                         (sb-thread:make-thread
                          (lambda ()
                            (with-isolated-suggestion-worker
                              (setf nshell.presentation::*suggestion-worker-state*
                                    state)
                              (nshell.presentation::%stop-suggestion-worker)
                              :stopped))
                          :name "suggestion worker stop test"))
                   (expect :stopped :to-equal
                           (sb-thread:join-thread stopper :default :timeout
                                                          :timeout 3))
                   (expect (sb-thread:thread-alive-p
                            (nshell.presentation::%suggestion-worker-state-thread
                             state))
                           :to-be-falsy)))
            ;; Release a reader the stop left blocked so no thread outlives
            ;; the test. O_RDWR opens a FIFO without blocking and pairs with
            ;; a reader still inside open(2).
            (ignore-errors
              (sb-posix:close
               (sb-posix:open fifo (logior sb-posix:o-rdwr sb-posix:o-nonblock))))
            (when stopper
              (ignore-errors (sb-thread:join-thread stopper :default nil :timeout 5)))
            (ignore-errors (delete-file fifo))
            (ignore-errors (sb-posix:rmdir directory)))))))

  (it "redraws when the key reader's idle poll delivers a worker result"
    ;; READ-KEY-CONT reads through the real READ-KEY-EVENT: with no key ready
    ;; it polls the worker and returns the redraw continuation.
    (with-repl-test-state
      (with-isolated-suggestion-worker
        (let ((renders 0)
              (nshell.presentation::*interactive-terminal-installed-p* t)
              (*standard-input* (make-string-input-stream "")))
          (unwind-protect
               (with-temporary-functions
                   (('nshell.presentation:compute-suggestion
                     (lambda (history input &rest arguments)
                       (declare (ignore history arguments))
                       (and (string= input "zzq") "-tail")))
                    ('nshell.infrastructure.acl:consume-terminal-resize-p
                     (lambda () nil))
                    ('nshell.presentation::%poll-assistant-model-event
                     (lambda () nil))
                    ('nshell.presentation::render-prompt-cont
                     (lambda () (incf renders) :rendered)))
                 (setf nshell.presentation::*input-state*
                       (nshell.presentation:make-input-state
                        :buffer "zzq" :cursor-pos 3))
                 (expect (nshell.presentation::%request-current-input-state-suggestion)
                         :to-be-truthy)
                 (let ((outcome
                         (handler-case
                             (sb-ext:with-timeout 5
                               (funcall (nshell.presentation::read-key-cont)))
                           (sb-ext:timeout () :timeout))))
                   (expect :rendered :to-equal outcome))
                 (expect 1 :to-equal renders)
                 (expect "-tail" :to-equal
                         (nshell.presentation::input-state-suggestion
                          nshell.presentation::*input-state*)))
            (nshell.presentation::%stop-suggestion-worker)))))))
