(in-package #:nshell.application)
(declaim
  (special
   nshell.infrastructure.acl:*command-not-found-hook*
   *function-call-depth*
   nshell.domain.expansion:*positional-args*
   nshell.infrastructure.persistence:*history-file-mutations-enabled-p*
   nshell.infrastructure.persistence::*history-file-path-override*
   *execution-origin*
   *execution-approval*
   *execution-gate-parent-kind*
   *execution-gate-refusal*
   *exec-exit-function*
   nshell.infrastructure.acl:*process-group-log*))

(define-condition byte-stream-execution-error (error)
  ((operation :initarg :operation :reader byte-stream-execution-error-operation)
   (cause :initarg :cause :reader byte-stream-execution-error-cause)))

(defvar *pipeline-stage-io* nil)

(defvar *pipeline-stage-exit-function* nil
  "In a pipeline stage thread, a function of a status that ends the stage
with that status, as when the stage's exec'd program has exited. The stage
unwinds to its own boundary, so the commands after exec in its body do not
run, and the pipeline then joins and closes every stage as usual. Once the
pipeline has ended, the thread that waited for it calls *EXEC-EXIT-FUNCTION*
with the pipeline's status. NIL outside a stage thread.")

(define-value-struct pipeline-execution-result
    ((status 0 :type integer)
     (stage-statuses nil :type list :copy :list)
     (stage-signals nil :type list :copy :list))
  :keyword-constructor t)

(defun make-pipeline-execution-result (status stage-statuses stage-signals)
  (%make-pipeline-execution-result
   :status status
   :stage-statuses stage-statuses
   :stage-signals stage-signals))

(define-value-struct pipeline-stage-io
    ((descriptor-map nil :type list :copy :list)
     (transient-descriptors nil :type list :copy :list)
     (preserved-descriptors nil :type list :copy :list)
     (default-standard-streams nil :type list :copy :list))
  :keyword-constructor t)

(defun make-pipeline-stage-io (descriptor-map transient-descriptors
                               &optional preserved-descriptors
                                 default-standard-streams)
  (%make-pipeline-stage-io
   :descriptor-map descriptor-map
   :transient-descriptors transient-descriptors
   :preserved-descriptors preserved-descriptors
   :default-standard-streams default-standard-streams))

(defstruct (pipeline-execution-handle
             (:constructor %make-pipeline-execution-handle (token)))
  (token nil :read-only t))

(defun command-node-external-p (context command-node)
  (multiple-value-bind (dispatch-kind binding)
      (nshell.application::%resolve-command-stage-binding context command-node)
    (declare (ignore binding))
    (eq dispatch-kind :external)))

(progn
  (defvar *pipeline-stage-stream-cache* nil)
  (defvar *pipeline-stage-stream-cache-active-p* nil)

  (defstruct (%byte-stream-execution-state
              (:constructor %make-byte-stream-execution-state))
    context
    stages
    stage-ios
    dispatcher
    processes
    threads
    statuses
    signals
    failures
    stream-caches
    ;; A stage ended through *PIPELINE-STAGE-EXIT-FUNCTION*.
    (exec-p nil))

  (defun %close-pipeline-stage-stream-cache (cache &optional abort)
    (let ((failure nil))
      (dolist (entry cache)
        (handler-case
            (close (cdr entry) :abort abort)
          (error (condition)
            (unless failure
              (setf failure condition)))))
      (when failure
        (error failure))))

  (defun %pipeline-stage-stream-from-descriptor (descriptor)
    (unless *pipeline-stage-stream-cache-active-p*
      (error "Pipeline stage streams are available only during stage dispatch."))
    (or (cdr (assoc descriptor *pipeline-stage-stream-cache*))
        (let ((fd (sb-posix:dup descriptor))
              (complete nil))
          (unwind-protect
               (let ((stream
                       (sb-sys:make-fd-stream
                        fd :input t :output t :buffering :none)))
                 (push (cons descriptor stream)
                       *pipeline-stage-stream-cache*)
                 (setf complete t)
                 stream)
            (unless complete
              (ignore-errors (sb-posix:close fd)))))))

  (defun %prepare-pipeline-stage-stream-cache (stage-io)
    (let ((*pipeline-stage-stream-cache* nil)
          (*pipeline-stage-stream-cache-active-p* t)
          (complete nil))
      (unwind-protect
           (progn
             (dolist (mapping
                      (nshell.application:pipeline-stage-io-descriptor-map
                       stage-io))
               (let ((source (cdr mapping)))
                 (when (integerp source)
                   (unless (<= 0 source)
                     (error "Invalid pipeline source descriptor: ~s" source))
                   (%pipeline-stage-stream-from-descriptor source))))
             (setf complete t)
             *pipeline-stage-stream-cache*)
        (unless complete
          (ignore-errors
            (%close-pipeline-stage-stream-cache
             *pipeline-stage-stream-cache*))))))

  (defun pipeline-stage-stream
      (descriptor &optional (stage-io *pipeline-stage-io*))
    (check-type descriptor (integer 0 *))
    (let ((mapping
            (assoc descriptor
                   (nshell.application:pipeline-stage-io-descriptor-map
                    stage-io)))
          (default-stream
            (assoc descriptor
                   (nshell.application:pipeline-stage-io-default-standard-streams
                    stage-io))))
      (cond
        (mapping
         (let ((source (cdr mapping)))
           (cond
             ((eq source :closed) :closed)
             ((typep source '(integer 0 *))
              (%pipeline-stage-stream-from-descriptor source))
             (t
              (error "Invalid pipeline source descriptor: ~s" source)))))
        (default-stream
         (cdr default-stream))
        ((= descriptor 0) *standard-input*)
        ((= descriptor 1) *standard-output*)
        ((= descriptor 2) *error-output*)
        (t (%pipeline-stage-stream-from-descriptor descriptor)))))
  (progn
  (defun %byte-stream-standard-stream (descriptor stage-io inherited)
    (let ((stream (pipeline-stage-stream descriptor stage-io)))
      (if (eq stream :closed)
          (let ((closed-stream
                  (if (zerop descriptor)
                      (make-string-input-stream "")
                      (make-string-output-stream))))
            (close closed-stream)
            closed-stream)
          (or stream inherited))))

  (defun %byte-stream-standard-source (descriptor stage-io)
    (let ((mapping
            (assoc descriptor
                   (pipeline-stage-io-descriptor-map stage-io)))
          (default-stream
            (assoc descriptor
                   (pipeline-stage-io-default-standard-streams stage-io))))
      (cond
        (mapping
         (let ((source (cdr mapping)))
           (cond
             ((eq source :closed) nil)
             ((typep source '(integer 0 *)) source)
             (t (error "Invalid pipeline source descriptor: ~s" source)))))
        (default-stream (cdr default-stream))
        (t t))))

  (defun %byte-stream-stage-argvs (context stages)
  (let ((argvs (make-array (length stages) :initial-element nil)))
    (loop for stage in stages
          for index from 0
          for kind = (evaluated-command-stage-dispatch-kind stage)
          when (or (member kind '(:external :source-function) :test #'eq)
                   (and (eq kind :builtin)
                        (eq :argv
                            (builtin-binding-argument-mode
                             (evaluated-command-stage-binding stage)))))
            do (setf (aref argvs index)
                     (command-argv-strings
                      context
                      (evaluated-command-stage-arguments stage))))
    argvs))

  (defun %cleanup-byte-stream-execution (state)
    (let ((processes
            (remove nil
                    (coerce (%byte-stream-execution-state-processes state)
                            'list))))
      (when processes
        (ignore-errors
          (nshell.infrastructure.acl::%terminate-pipeline-processes
           (reverse processes))))
      (loop for thread across (%byte-stream-execution-state-threads state)
            when (and thread (sb-thread:thread-alive-p thread))
              do (ignore-errors (sb-thread:terminate-thread thread)))
      (loop for thread across (%byte-stream-execution-state-threads state)
            when thread
              do (ignore-errors (sb-thread:join-thread thread)))
      (loop for cache across (%byte-stream-execution-state-stream-caches state)
            when cache
              do (ignore-errors (%close-pipeline-stage-stream-cache cache)))
      (dolist (process processes)
        (ignore-errors (nshell.infrastructure.acl:process-close process))))
    state)

  (defun %broken-pipe-failure-p (condition)
    "True when CONDITION is EPIPE or wraps one through CAUSE slots.
A nested pipeline's EPIPE reaches the enclosing stage inside the
execution errors that wrap it on the way out."
    (loop for current = condition
            then (and (slot-exists-p current 'cause)
                      (slot-boundp current 'cause)
                      (slot-value current 'cause))
          while (typep current 'condition)
          thereis (typep current 'sb-int:broken-pipe)))

  (defun %byte-stream-launch-thread (state index thunk)
  (let ((stage-io (nth index (%byte-stream-execution-state-stage-ios state)))
        (cache (aref (%byte-stream-execution-state-stream-caches state) index))
        (command-not-found-hook
          nshell.infrastructure.acl:*command-not-found-hook*)
        (history-file-mutations-enabled-p
          nshell.infrastructure.persistence:*history-file-mutations-enabled-p*)
        (history-file-path-override
          nshell.infrastructure.persistence::*history-file-path-override*)
        (function-call-depth *function-call-depth*)
        ;; A stage thread runs AI-originated functions under the same gate.
        (execution-origin *execution-origin*)
        (execution-approval *execution-approval*)
        (execution-gate-parent-kind *execution-gate-parent-kind*)
        (execution-gate-refusal *execution-gate-refusal*)
        ;; exec in a stage ends the run the way the caller decided, and the
        ;; stage's processes join the caller's record of process groups.
        (exec-exit-function *exec-exit-function*)
        (process-group-log nshell.infrastructure.acl:*process-group-log*)
        (positional-args
          (copy-list nshell.domain.expansion:*positional-args*))
        (upstream-stage-p
          (< index (1- (length (%byte-stream-execution-state-stages state)))))
        (broken-pipe-p nil))
    (setf (aref (%byte-stream-execution-state-threads state) index)
          (sb-thread:make-thread
           (lambda ()
             (let ((nshell.domain.expansion:*positional-args* positional-args)
                   (*pipeline-stage-io* stage-io)
                   (nshell.infrastructure.acl:*command-not-found-hook*
                     command-not-found-hook)
                   (*pipeline-stage-stream-cache* cache)
                   (*pipeline-stage-stream-cache-active-p* t)
                   (nshell.infrastructure.persistence:*history-file-mutations-enabled-p*
                     history-file-mutations-enabled-p)
                   (nshell.infrastructure.persistence::*history-file-path-override*
                     history-file-path-override)
                   (*foreground-terminal-runner* nil)
                   (*function-call-depth* function-call-depth)
                   (*execution-origin* execution-origin)
                   (*execution-approval* execution-approval)
                   (*execution-gate-parent-kind* execution-gate-parent-kind)
                   (*execution-gate-refusal* execution-gate-refusal)
                   (*exec-exit-function* exec-exit-function)
                   (nshell.infrastructure.acl:*process-group-log* process-group-log))
               (unwind-protect
                    (handler-case
                        (let ((*standard-input*
                                (%byte-stream-standard-stream
                                 0 stage-io *standard-input*))
                              (*standard-output*
                                (%byte-stream-standard-stream
                                 1 stage-io *standard-output*))
                              (*error-output*
                                (%byte-stream-standard-stream
                                 2 stage-io *error-output*))
                              (stage-exit (list :pipeline-stage-exit)))
                          (catch stage-exit
                            (let ((*pipeline-stage-exit-function*
                                    (lambda (status)
                                      (setf (aref (%byte-stream-execution-state-statuses state)
                                                  index)
                                            status
                                            (aref (%byte-stream-execution-state-signals state)
                                                  index)
                                            nil
                                            (%byte-stream-execution-state-exec-p state)
                                            t)
                                      (throw stage-exit nil))))
                              (funcall thunk))))
                      ;; A forked shell stage dies of SIGPIPE when its reader
                      ;; exits first. SBCL ignores SIGPIPE, so an in-process
                      ;; upstream stage sees EPIPE instead and gets the same
                      ;; 128+SIGPIPE status; the last stage keeps failing.
                      (error (condition)
                        (if (and upstream-stage-p
                                 (%broken-pipe-failure-p condition))
                            (setf broken-pipe-p t
                                  (aref (%byte-stream-execution-state-statuses state)
                                        index)
                                  (+ 128 sb-unix:sigpipe)
                                  (aref (%byte-stream-execution-state-signals state)
                                        index)
                                  sb-unix:sigpipe)
                            (setf (aref (%byte-stream-execution-state-failures state)
                                        index)
                                  condition))))
                 (handler-case
                     ;; Output left unwritten by EPIPE would fail again on flush.
                     (%close-pipeline-stage-stream-cache cache broken-pipe-p)
                   (error (condition)
                     (unless (aref (%byte-stream-execution-state-failures state)
                                   index)
                       (setf (aref (%byte-stream-execution-state-failures state)
                                   index)
                             condition)))))))
           :name (format nil "nshell pipeline stage ~d" index)))
    state))

  (defun spawn-byte-stream-node-in-context
  (context evaluated-stages stage-ios internal-stage-dispatcher)
(let* ((stages (copy-list evaluated-stages))
       (stage-io-list (copy-list stage-ios))
       (count (length stages)))
  (unless (= count (length stage-io-list))
    (error "Pipeline stage and descriptor-map counts differ."))
  (let* ((argvs (%byte-stream-stage-argvs context stages))
         (processes (make-array count :initial-element nil))
         (threads (make-array count :initial-element nil))
         (statuses (make-array count :initial-element nil))
         (signals (make-array count :initial-element nil))
         (failures (make-array count :initial-element nil))
         (stream-caches (make-array count :initial-element nil))
         (state
           (%make-byte-stream-execution-state
            :context context
            :stages stages
            :stage-ios stage-io-list
            :dispatcher internal-stage-dispatcher
            :processes processes
            :threads threads
            :statuses statuses
            :signals signals
            :failures failures
            :stream-caches stream-caches))
         (environments
           (map 'vector
                (lambda (stage)
                  (or (%stage-environment-strings
                       context
                       (evaluated-command-stage-environment-assignments
                        stage))
                      (%context-exported-environment-strings context)
                      (nshell.infrastructure.acl::external-command-environment)))
                stages))
         (resolved-commands (make-array count :initial-element nil))
         (process-group nil))
    (handler-case
        (progn
          (loop for stage in stages
                for index from 0
                when (eq :external
                         (evaluated-command-stage-dispatch-kind stage))
                  do (setf (aref resolved-commands index)
                           (nshell.infrastructure.acl::%resolve-external-command
                            (nshell.domain.parsing:command-node-command
                             (evaluated-command-stage-command-node stage))
                            (aref environments index))))
          (loop for stage in stages
                for index from 0
                for kind = (evaluated-command-stage-dispatch-kind stage)
                when (or (member kind
                                 '(:builtin :shell-function :source-function)
                                 :test #'eq)
                         (and (eq kind :external)
                              (null (aref resolved-commands index))))
                  do (setf (aref stream-caches index)
                           (%prepare-pipeline-stage-stream-cache
                            (nth index stage-io-list))))
          (loop for stage in stages
                for index from 0
                for kind = (evaluated-command-stage-dispatch-kind stage)
                for stage-io = (nth index stage-io-list)
                do (case kind
                     (:external
                      (let ((command
                              (nshell.domain.parsing:command-node-command
                               (evaluated-command-stage-command-node stage)))
                            (resolved (aref resolved-commands index)))
                        (if resolved
                            (let ((process
                                    (nshell.infrastructure.acl::%spawn-external-command
                                     resolved
                                     (aref argvs index)
                                     (aref environments index)
                                     :input (%byte-stream-standard-source
                                             0 stage-io)
                                     :output (%byte-stream-standard-source
                                              1 stage-io)
                                     :error (%byte-stream-standard-source
                                             2 stage-io)
                                     :preserve-fds
                                     (pipeline-stage-io-preserved-descriptors
                                      stage-io)
                                     :process-group (or process-group :new))))
                              (setf (aref processes index) process)
                              (unless process-group
                                (setf process-group
                                      (nshell.infrastructure.acl:process-pid
                                       process))))
                            (let ((stage-index index))
                              (setf (aref statuses stage-index) 127)
                              (%byte-stream-launch-thread
                               state stage-index
                               (lambda ()
                                 (write-string
                                  (nshell.infrastructure.acl::%external-command-not-found-message command)
                                  *error-output*)))))))
                     ((:builtin :shell-function :source-function)
                      (let ((stage-to-dispatch stage)
                            (stage-io-to-dispatch stage-io)
                            (stage-index index))
                        (%byte-stream-launch-thread
                         state stage-index
                         (lambda ()
                           (multiple-value-bind (status signal)
                               (funcall internal-stage-dispatcher
                                        context
                                        stage-to-dispatch
                                        stage-io-to-dispatch
                                        (aref argvs stage-index))
                             (unless (integerp status)
                               (error "Pipeline dispatcher returned a non-integer status: ~s"
                                      status))
                             (unless (or (null signal)
                                         (and (integerp signal) (plusp signal)))
                               (error "Pipeline dispatcher returned an invalid signal: ~s"
                                      signal))
                             (setf (aref statuses stage-index) status
                                   (aref signals stage-index) signal)))))
                      )
                     (otherwise
                      (error "Unsupported evaluated pipeline stage kind: ~s"
                             kind))))
          (%make-pipeline-execution-handle state))
      (error (condition)
        (%cleanup-byte-stream-execution state)
        (error 'byte-stream-execution-error
               :operation :start
               :cause condition))))))

  (defun %byte-stream-process-signal (process)
    (when (eq :signaled
              (nshell.infrastructure.acl:process-status process))
      (nshell.infrastructure.acl::native-process-exit-code process)))

  (defun wait-byte-stream-execution (handle)
    "Wait for every stage of HANDLE's pipeline, close it, and return its
result. When a stage ended by exec, call *EXEC-EXIT-FUNCTION* with the
pipeline's status once the pipeline has ended."
    (let* ((state (pipeline-execution-handle-token handle))
           (result (%wait-byte-stream-execution-state state)))
      (when (%byte-stream-execution-state-exec-p state)
        (funcall *exec-exit-function* (pipeline-execution-result-status result)))
      result))

  (defun %wait-byte-stream-execution-state (state)
    (handler-case
        (progn
          (loop for process across (%byte-stream-execution-state-processes state)
                for index from 0
                when process
                  do (nshell.infrastructure.acl:process-wait process)
                     (setf (aref (%byte-stream-execution-state-statuses state)
                                 index)
                           (nshell.infrastructure.acl:process-exit-status-code
                            process)
                           (aref (%byte-stream-execution-state-signals state)
                                 index)
                           (%byte-stream-process-signal process)))
          (loop for thread across (%byte-stream-execution-state-threads state)
                when thread
                  do (sb-thread:join-thread thread))
          (let ((failure
                  (find-if #'identity
                           (coerce (%byte-stream-execution-state-failures state)
                                   'list))))
            (when failure
              (error failure)))
          (let ((stage-statuses
                  (coerce (%byte-stream-execution-state-statuses state) 'list))
                (stage-signals
                  (coerce (%byte-stream-execution-state-signals state) 'list)))
            (unless (every #'integerp stage-statuses)
              (error "Pipeline stages completed without integer statuses: ~s"
                     stage-statuses))
            (loop for process across (%byte-stream-execution-state-processes state)
                  when process
                    do (nshell.infrastructure.acl:process-close process))
            (loop for cache across (%byte-stream-execution-state-stream-caches state)
                  when cache
                    do (%close-pipeline-stage-stream-cache cache))
            (make-pipeline-execution-result
             (if (shell-context-pipefail-p
                  (%byte-stream-execution-state-context state))
                 (or (find-if (lambda (status) (not (zerop status)))
                              stage-statuses)
                     0)
                 (or (car (last stage-statuses)) 0))
             stage-statuses
             stage-signals)))
      (error (condition)
        (%cleanup-byte-stream-execution state)
        (error 'byte-stream-execution-error
               :operation :wait
               :cause condition))))))
