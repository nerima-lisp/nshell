(in-package #:nshell.application)

(define-condition command-execution-plan-error (error)
  ((source-span :initarg :source-span
                :reader command-execution-plan-error-source-span)
   (operation :initarg :operation
              :reader command-execution-plan-error-operation)
   (cause :initarg :cause :reader command-execution-plan-error-cause))
  (:report
   (lambda (condition stream)
     (format stream
             "Command execution plan failed during ~S: ~A"
             (command-execution-plan-error-operation condition)
             (command-execution-plan-error-cause condition)))))

(declaim
  (special nshell.infrastructure.acl:*exported-environment*)
  (special *foreground-terminal-runner*)
  (special *function-call-depth*)
  (special *command-evaluation-position*)
  (ftype
   (function (t t function &optional function)
    (values t integer pipeline-execution-result))
   execute-reader-ast-in-context))
(defun execute-reader-ast-in-context
    (context ast stage-evaluator &optional command-failure-policy)
  (multiple-value-bind (value status result)
      (cond
        ((nshell.domain.parsing:sequence-node-p ast)
         (%execute-reader-sequence-node-in-context
          context ast stage-evaluator command-failure-policy))
        ((or (nshell.domain.parsing:command-node-p ast)
             (nshell.domain.parsing:pipeline-node-p ast))
         (%reader-execute-foreground-in-context
          context ast stage-evaluator))
        (t
         (error (quote command-execution-plan-error)
                :source-span
                (and (nshell.domain.parsing::ast-node-p ast)
                     (nshell.domain.parsing:ast-node-span ast))
                :operation :dispatch
                :cause
                (make-condition (quote simple-error)
                                :format-control "Unsupported reader AST node."
                                :format-arguments nil))))
    (%record-last-exit-code context status)
    (values value status result)))

(defstruct (%reader-execution-state
             (:constructor %make-reader-execution-state ()))
  (descriptors nil)
  (process-substitutions nil))

(defstruct (%reader-process-substitution
             (:constructor %make-reader-process-substitution
                 (entry resource handle stage-index)))
  entry
  resource
  handle
  stage-index)

(defun %reader-plan-error (source-span operation cause)
  (error 'command-execution-plan-error
         :source-span source-span
         :operation operation
         :cause cause))

(defun %reader-allocate-with-plan-error (source-span allocator)
  (handler-case
      (funcall allocator)
    (command-execution-plan-error (condition)
      (error condition))
    (command-argument-type-error (condition)
      (error condition))
    (error (condition)
      (%reader-plan-error source-span :allocate condition))))

(defun %reader-simple-condition (control &rest arguments)
  (make-condition 'simple-error
                  :format-control control
                  :format-arguments arguments))

(defun %reader-own-descriptor (state descriptor &optional source-span)
  (unless (and (integerp descriptor) (<= 0 descriptor))
    (%reader-plan-error source-span
                        :allocate
                        (%reader-simple-condition
                         "Reader execution allocated an invalid descriptor.")))
  (pushnew descriptor
           (%reader-execution-state-descriptors state)
           :test #'eql)
  descriptor)

(defun %reader-close-owned-descriptor (state descriptor)
  (when (member descriptor (%reader-execution-state-descriptors state)
                :test #'eql)
    (setf (%reader-execution-state-descriptors state)
          (remove descriptor
                  (%reader-execution-state-descriptors state)
                  :test #'eql))
    (nshell.infrastructure.acl::close-reader-descriptor descriptor)))

(defun %reader-close-owned-descriptors (state &optional keep)
  (dolist (descriptor (copy-list
                       (%reader-execution-state-descriptors state)))
    (unless (member descriptor keep :test #'eql)
      (%reader-close-owned-descriptor state descriptor))))

(defun %reader-cleanup-execution-state (state)
  (dolist (descriptor
           (copy-list (%reader-execution-state-descriptors state)))
    (ignore-errors (%reader-close-owned-descriptor state descriptor)))
  (dolist (substitution
           (%reader-execution-state-process-substitutions state))
    (let ((handle (%reader-process-substitution-handle substitution)))
      (when handle
        (ignore-errors (wait-byte-stream-execution handle))
        (setf (%reader-process-substitution-handle substitution) nil)))))

(defun %reader-redirect-destination-descriptors (command-node)
  (loop for redirect in
        (nshell.domain.parsing:command-node-redirects command-node)
        append
        (case (nshell.domain.parsing:ast-redirect-entry-kind redirect)
          ((:both-output-files :append-both-output-files) '(1 2))
          ((:process-substitution-input :process-substitution-output) nil)
          (otherwise
           (list
            (nshell.domain.parsing:ast-redirect-entry-file-descriptor
             redirect))))))

(defun %reader-command-stages (ast)
  (cond
    ((nshell.domain.parsing:command-node-p ast) (list ast))
    ((nshell.domain.parsing:pipeline-node-p ast)
     (nshell.domain.parsing:pipeline-node-commands ast))
    (t nil)))

(defun %reader-pipeline-edges (ast)
  (when (nshell.domain.parsing:pipeline-node-p ast)
    (let* ((commands (nshell.domain.parsing:pipeline-node-commands ast))
           (edges (nshell.domain.parsing:pipeline-node-edges ast)))
      (or edges
          (loop repeat (max 0 (1- (length commands)))
                collect (nshell.domain.parsing:make-pipeline-edge :pipe))))))

(defun %reader-preflight-process-substitutions (context stages)
  (let ((entries nil))
    (loop for command in stages
          for stage-index from 0
          do (dolist (entry
                      (nshell.domain.parsing:command-node-redirects command))
               (let ((target
                       (nshell.domain.parsing:ast-redirect-entry-target entry)))
                 (when (nshell.domain.parsing:redirect-procsub-target-p target)
                   (let ((inner-commands
                           (%preflight-reader-process-substitution-entry entry)))
                     (dolist (inner-command inner-commands)
                       (multiple-value-bind (dispatch-kind binding)
                           (%resolve-command-stage-binding context inner-command)
                         (unless (or (eq dispatch-kind :external)
                                     (and (eq dispatch-kind :builtin)
                                          (eq :argv
                                              (builtin-binding-argument-mode
                                               binding))))
                           (%reader-plan-error
                            (nshell.domain.parsing:ast-redirect-entry-source-span
                             entry)
                            :preflight
                            (%reader-simple-condition
                             "Process substitution requires external commands or :argv builtins.")))))
                     (push (list stage-index entry inner-commands) entries))))))
    (nreverse entries)))

(defun %reader-find-evaluated-redirect-target (evaluated-stage redirect)
  (cdr (assoc
        (nshell.domain.parsing:ast-redirect-entry-source-order redirect)
        (nshell.application:evaluated-command-stage-redirect-target-values
         evaluated-stage)
        :test #'eql)))

(defun %reader-make-evaluated-stage-with-arguments (stage arguments)
  (nshell.application:make-evaluated-command-stage
   (nshell.application:evaluated-command-stage-command-node stage)
   (nshell.application:evaluated-command-stage-dispatch-kind stage)
   (nshell.application:evaluated-command-stage-binding stage)
   arguments
   (nshell.application:evaluated-command-stage-redirect-target-values stage)
   (nshell.application:evaluated-command-stage-environment-assignments stage)))

(defun %reader-resolve-descriptor (bindings descriptor)
  (multiple-value-bind (value present-p)
      (gethash descriptor (car bindings))
    (if present-p value descriptor)))

(defun %reader-set-descriptor (bindings destination source)
  (setf (cdr bindings)
        (append (remove destination (cdr bindings))
                (list destination)))
  (setf (gethash destination (car bindings)) source))

(defun %reader-binding-alist (bindings)
  (loop for destination in (cdr bindings)
        collect (cons destination
                      (gethash destination (car bindings)))))

(defun %reader-stage-io-list
    (bindings state
     &optional
       (process-substitutions
        (%reader-execution-state-process-substitutions state)))
  (loop for stage-bindings in bindings
        for stage-index from 0
        collect
        (let ((process-substitution-fds
                (loop for substitution in process-substitutions
                      when (= stage-index
                              (%reader-process-substitution-stage-index
                               substitution))
                        collect
                        (nshell.infrastructure.acl::reader-process-substitution-resource-parent-fd
                         (%reader-process-substitution-resource
                          substitution)))))
          (make-pipeline-stage-io
           (%reader-binding-alist stage-bindings)
           process-substitution-fds
           process-substitution-fds
           (list (cons 0 *standard-input*)
                 (cons 1 *standard-output*)
                 (cons 2 *error-output*))))))

(defun %reader-open-redirect (context state redirect evaluated-stage)
  (let* ((target
           (nshell.domain.parsing:ast-redirect-entry-target redirect))
         (evaluated-target
           (when (nshell.domain.parsing:command-arg-p target)
             (%reader-find-evaluated-redirect-target
              evaluated-stage redirect)))
         (span
           (nshell.domain.parsing:ast-redirect-entry-source-span redirect)))
    (when (and (nshell.domain.parsing:command-arg-p target)
               (null evaluated-target))
      (%reader-plan-error
       span :redirect-target
       (%reader-simple-condition
        "Reader redirect target was not evaluated.")))
    (handler-case
        (%reader-own-descriptor
         state
         (%open-reader-redirect-source
          context redirect evaluated-target
          :avoid-descriptors
          (remove-duplicates
           (append (%reader-execution-state-descriptors state)
                   (%reader-redirect-destination-descriptors
                    (nshell.application:evaluated-command-stage-command-node
                     evaluated-stage))
                   '(0 1 2))
           :test #'eql)))
      (nshell.domain.expansion:parameter-expansion-error (condition)
        (error condition))
      (command-argument-type-error (condition)
        (error condition))
      (command-failed (condition)
        (error condition))
      (command-execution-plan-error (condition)
        (error condition))
      (error (condition)
        (%reader-plan-error span :open condition)))))

(defun %reader-process-substitution-for-entry (state stage-index entry)
  (find-if (lambda (substitution)
             (and (= stage-index
                     (%reader-process-substitution-stage-index substitution))
                  (eq entry
                      (%reader-process-substitution-entry substitution))))
           (%reader-execution-state-process-substitutions state)))

(defun %reader-register-process-substitution
    (state stage-index entry resource)
  (let ((substitution
          (%make-reader-process-substitution
           entry resource nil stage-index)))
    (push substitution
          (%reader-execution-state-process-substitutions state))
    substitution))

(defun %reader-process-substitution-endpoint (state stage-index entry)
  (let* ((substitution
           (%reader-process-substitution-for-entry state stage-index entry))
         (resource
           (and substitution
                (%reader-process-substitution-resource substitution))))
    (unless resource
      (%reader-plan-error
       (nshell.domain.parsing:ast-redirect-entry-source-span entry)
       :process-substitution
       (%reader-simple-condition
        "Process substitution resource was not prepared.")))
    (nshell.infrastructure.acl::reader-process-substitution-resource-parent-fd
     resource)))

(defclass %reader-closed-input-stream
    (sb-gray:fundamental-character-input-stream)
  ())

(defmethod sb-gray:stream-read-char ((stream %reader-closed-input-stream))
  (error 'stream-error :stream stream))

(defmethod sb-gray:stream-unread-char
    ((stream %reader-closed-input-stream) character)
  (declare (ignore character))
  (error 'stream-error :stream stream))

(defmethod sb-gray:stream-listen ((stream %reader-closed-input-stream))
  (error 'stream-error :stream stream))

(defclass %reader-closed-output-stream
    (sb-gray:fundamental-character-output-stream)
  ())

(defmethod sb-gray:stream-write-char
    ((stream %reader-closed-output-stream) character)
  (declare (ignore character))
  (error 'stream-error :stream stream))

(defmethod sb-gray:stream-write-string
    ((stream %reader-closed-output-stream) string &optional start end)
  (declare (ignore string start end))
  (error 'stream-error :stream stream))

(defmethod sb-gray:stream-force-output
    ((stream %reader-closed-output-stream))
  (error 'stream-error :stream stream))

(defmethod sb-gray:stream-finish-output
    ((stream %reader-closed-output-stream))
  (error 'stream-error :stream stream))

(defun %reader-stage-standard-stream (descriptor stage-io)
  (let ((stream (pipeline-stage-stream descriptor stage-io)))
    (if (eq stream :closed)
        (if (zerop descriptor)
            (make-instance '%reader-closed-input-stream)
            (make-instance '%reader-closed-output-stream))
        stream)))

(defun %reader-dispatch-internal-stage
    (context evaluated-stage stage-io argv-strings &optional single-stage-p)
  (flet ((stage-context (&optional isolate-environment-p)
           (let ((assignments
                   (nshell.application:evaluated-command-stage-environment-assignments
                    evaluated-stage)))
             (if (and (null assignments)
                      (not isolate-environment-p))
                 context
                 (make-shell-context
                  :history (shell-context-history context)
                  :config (shell-context-config context)
                  :knowledge-base (shell-context-knowledge-base context)
                  :environment
                  (reduce
                   (lambda (environment assignment)
                     (nshell.domain.environment:env-set
                      environment (car assignment) (cdr assignment) t
                      :scope :global))
                   assignments
                   :initial-value
                   (%environment-with-assignments
                    (shell-context-environment context)
                    assignments))
                  :filesystem (shell-context-filesystem context)
                  :job-monitor (shell-context-job-monitor context)
                  :alias-table (shell-context-alias-table context)
                  :sexp-alias-table (shell-context-sexp-alias-table context)
                  :abbreviation-table
                  (shell-context-abbreviation-table context)
                  :function-table (shell-context-function-table context)
                  :function-source-table
                  (shell-context-function-source-table context)
                  :shell-function-registry
                  (make-shell-function-registry
                   (shell-function-registry-global-table
                    (shell-context-shell-function-registry context)))
                  :execution-strategy
                  (shell-context-execution-strategy context)
                  :pipefail-p (shell-context-pipefail-p context)
                  :running (shell-context-running context)
                  :last-exit-code (shell-context-last-exit-code context)
                  :input-state (shell-context-input-state context)
                  :process-registry (shell-context-process-registry context)
                  :terminal-rows (shell-context-terminal-rows context)
                  :terminal-cols (shell-context-terminal-cols context))))))
    (let* ((binding
             (nshell.application:evaluated-command-stage-binding
              evaluated-stage))
           (dispatch-kind
             (nshell.application:evaluated-command-stage-dispatch-kind
              evaluated-stage))
           ;; Function stages must not replace a sibling stage's context.
           (context
             (stage-context
             (and (or (eq dispatch-kind :source-function)
                  (eq dispatch-kind :shell-function))
                  (not single-stage-p))))
           (nshell.infrastructure.acl:*exported-environment*
             (%context-exported-environment-strings context))
           (*pipeline-stage-io* stage-io)
           (*standard-input* (%reader-stage-standard-stream 0 stage-io))
           (*standard-output* (%reader-stage-standard-stream 1 stage-io))
           (*error-output* (%reader-stage-standard-stream 2 stage-io)))
      (ecase dispatch-kind
        (:builtin
         (when (eq :value (builtin-binding-argument-mode binding))
           (%reader-plan-error
            (nshell.domain.parsing:ast-node-span
             (nshell.application:evaluated-command-stage-command-node
              evaluated-stage))
            :dispatch
            (%reader-simple-condition
             "A value builtin cannot run as a byte-stream stage.")))
         (multiple-value-bind (output status)
             (dispatch-builtin
              context binding
              (nshell.application:evaluated-command-stage-arguments
               evaluated-stage)
              :argv-strings argv-strings)
           (when (and output
                     (not (member *command-evaluation-position*
                                  (quote (:test :status-value))
                                  :test (function eq))))
             (write-string output *standard-output*))
           (values status nil)))
        (:shell-function
         (when (>= *function-call-depth* 128)
           (error "function recursion limit exceeded"))
         (let ((*function-call-depth* (1+ *function-call-depth*)))
           (handler-case
               (progn
                 (funcall
                  (shell-function-binding-callable binding)
                  context
                  (nshell.application:evaluated-command-stage-arguments
                   evaluated-stage)
                  :stream)
                 (values 0 nil))
             (command-failed (condition)
               (values (command-failed-status condition)
                       (command-failed-signal condition))))))
        (:source-function
         (handler-case
             (multiple-value-bind (output status)
                 (%execute-function-command-in-context context binding argv-strings :output-mode :stream)
               (when output
                 (write-string output *standard-output*))
               (values status nil))
           (command-failed (condition)
             (values (command-failed-status condition)
                     (command-failed-signal condition)))))))))

(defun %reader-rewrite-process-substitution-arguments
    (state stage-index evaluated-stage)
  (let* ((command
           (nshell.application:evaluated-command-stage-command-node
            evaluated-stage))
         (arguments
           (nshell.application:evaluated-command-stage-arguments
            evaluated-stage)))
    (dolist (entry (nshell.domain.parsing:command-node-redirects command))
      (when (member
             (nshell.domain.parsing:ast-redirect-entry-kind entry)
             '(:process-substitution-input :process-substitution-output))
        (let* ((resource
                 (let ((substitution
                         (%reader-process-substitution-for-entry
                          state stage-index entry)))
                   (and substitution
                        (%reader-process-substitution-resource
                         substitution))))
               (fd
                 (and resource
                      (nshell.infrastructure.acl::reader-process-substitution-resource-parent-fd
                       resource)))
               (path
                 (and fd
                      (nshell.infrastructure.acl::reader-process-substitution-fd-path
                       fd)))
               (matched-p nil))
          (unless path
            (%reader-plan-error
             (nshell.domain.parsing:ast-redirect-entry-source-span entry)
             :process-substitution
             (%reader-simple-condition
              "Process substitution path descriptor is unavailable.")))
          (setf arguments
                (mapcar
                 (lambda (argument)
                   (if (equal
                        (nshell.domain.parsing:evaluated-command-arg-source-span
                         argument)
                        (nshell.domain.parsing:ast-redirect-entry-source-span
                         entry))
                       (progn
                         (setf matched-p t)
                         (nshell.domain.parsing:make-evaluated-command-arg
                          path
                          (nshell.domain.parsing:evaluated-command-arg-source-span
                           argument)
                          (nshell.domain.parsing:evaluated-command-arg-glob-p
                           argument)
                          (nshell.domain.parsing:evaluated-command-arg-expand-p
                           argument)))
                       argument))
                 arguments))
          (unless matched-p
            (%reader-plan-error
             (nshell.domain.parsing:ast-redirect-entry-source-span entry)
             :process-substitution
             (%reader-simple-condition
              "Process substitution argument has no evaluated source span."))))))
    (%reader-make-evaluated-stage-with-arguments
     evaluated-stage arguments)))

(defun %reader-build-stage-bindings
    (context state ast evaluated-stages &key input-fd output-fd)
  (let* ((commands (%reader-command-stages ast))
         (edges (%reader-pipeline-edges ast))
         (pipe-endpoints nil)
         (bindings (mapcar (lambda (ignored)
                             (declare (ignore ignored))
                             (cons (make-hash-table :test #'eql) nil))
                           commands)))
    (when (and input-fd commands)
      (%reader-set-descriptor (first bindings) 0 input-fd))
    (when (and output-fd commands)
      (%reader-set-descriptor (car (last bindings)) 1 output-fd))
    (loop for edge in edges
          for index from 0
          for source-span =
            (or (nshell.domain.parsing:pipeline-edge-source-span edge)
                (nshell.domain.parsing:ast-node-span ast))
          do (multiple-value-bind (read-fd write-fd)
                 (%reader-allocate-with-plan-error
                  source-span
                  (lambda ()
                    (nshell.infrastructure.acl::make-reader-pipeline-pipe
                     :avoid-descriptors
                     (append (%reader-execution-state-descriptors state)
                             '(0 1 2)))))
               (push (list read-fd write-fd source-span) pipe-endpoints)
               (%reader-own-descriptor state read-fd source-span)
               (%reader-own-descriptor state write-fd source-span)
               (%reader-set-descriptor (nth index bindings) 1 write-fd)
               (%reader-set-descriptor (nth (1+ index) bindings) 0 read-fd)))
    (loop for command in commands
          for evaluated-stage in evaluated-stages
          for stage-index from 0
          for stage-bindings in bindings
          do (dolist (redirect
                      (stable-sort
                       (copy-list
                        (nshell.domain.parsing:command-node-redirects
                         command))
                       #'<
                       :key #'nshell.domain.parsing:ast-redirect-entry-source-order))
               (let* ((kind
                        (nshell.domain.parsing:ast-redirect-entry-kind
                         redirect))
                      (target
                        (nshell.domain.parsing:ast-redirect-entry-target
                         redirect))
                      (destination
                        (nshell.domain.parsing:ast-redirect-entry-file-descriptor
                         redirect)))
                 (cond
                   ((member kind
                            '(:process-substitution-input
                              :process-substitution-output))
                    (let ((fd
                            (%reader-process-substitution-endpoint
                             state stage-index redirect)))
                      (%reader-set-descriptor stage-bindings fd fd)))
                   ((member kind
                            '(:duplicate-input-fd
                              :duplicate-output-fd))
                    (%reader-set-descriptor
                     stage-bindings destination
                     (if (nshell.domain.parsing:redirect-fd-close-target-p
                          target)
                         :closed
                         (%reader-resolve-descriptor
                          stage-bindings
                          (nshell.domain.parsing:redirect-fd-target-file-descriptor
                           target)))))
                   ((nshell.domain.parsing:redirect-procsub-target-p target)
                    (%reader-set-descriptor
                     stage-bindings destination
                     (%reader-process-substitution-endpoint
                      state stage-index redirect)))
                   (t
                    (let ((source
                            (%reader-open-redirect
                             context state redirect evaluated-stage)))
                      (when (integerp destination)
                        (%reader-set-descriptor
                         stage-bindings destination source))
                      (when (member kind
                                    '(:both-output-files
                                      :append-both-output-files))
                        (%reader-set-descriptor stage-bindings 1 source)
                        (%reader-set-descriptor stage-bindings 2 source))))))))
    (loop for (read-fd write-fd source-span) in (nreverse pipe-endpoints)
          for index from 0
          for upstream-bindings = (nth index bindings)
          for downstream-bindings = (nth (1+ index) bindings)
          when (and (not (eql (%reader-resolve-descriptor
                               downstream-bindings 0)
                              read-fd))
                    (eql (%reader-resolve-descriptor upstream-bindings 1)
                         write-fd))
            do (let ((discard-fd
                       (%reader-allocate-with-plan-error
                        source-span
                        (lambda ()
                          (nshell.infrastructure.acl::open-reader-redirect-file
                           "/dev/null" :append
                           :avoid-descriptors
                           (append
                            (%reader-execution-state-descriptors state)
                            '(0 1 2)))))))
                 (%reader-own-descriptor state discard-fd source-span)
                 (%reader-set-descriptor upstream-bindings 1 discard-fd)))
    (loop for edge in edges
          for index from 0
          when (eq :pipe-stderr-to-stdout
                   (nshell.domain.parsing:pipeline-edge-kind edge))
            do (%reader-set-descriptor
                (nth index bindings)
                2
                (%reader-resolve-descriptor
                 (nth index bindings) 1)))
    bindings))

(defun %reader-evaluate-stages (context commands stage-evaluator)
  (mapcar (lambda (command)
            (funcall stage-evaluator context command))
          commands))
(defun %reader-run-single-internal-stage
    (context evaluated-stages stage-io-list)
  (when (and (= 1 (length evaluated-stages))
             (member
              (nshell.application:evaluated-command-stage-dispatch-kind
               (first evaluated-stages))
              '(:builtin :shell-function :source-function)
              :test #'eq))
    (let* ((stage (first evaluated-stages))
           (stage-io (first stage-io-list))
           (stream-cache
             (%prepare-pipeline-stage-stream-cache stage-io))
           (argvs (%byte-stream-stage-argvs context evaluated-stages)))
      (unwind-protect
           (multiple-value-bind (status signal)
               (let ((*pipeline-stage-stream-cache* stream-cache)
                     (*pipeline-stage-stream-cache-active-p* t))
                 (%reader-dispatch-internal-stage
                  context stage stage-io (aref argvs 0) t))
             (unless (integerp status)
               (error "Pipeline dispatcher returned a non-integer status: ~s"
                      status))
             (unless (or (null signal)
                         (and (integerp signal) (plusp signal)))
               (error "Pipeline dispatcher returned an invalid signal: ~s"
                      signal))
             (make-pipeline-execution-result status (list status) (list signal)))
        (%close-pipeline-stage-stream-cache stream-cache)))))
(defun %reader-terminal-external-dispatch (context ast plans evaluated-stages)
  (labels ((terminal-command (stage)
           (let ((command-node
                   (nshell.application:evaluated-command-stage-command-node
                    stage)))
             (nshell.domain.parsing:make-command-node
              (nshell.domain.parsing:command-node-command command-node)
              (command-argv-strings
               context
               (nshell.application:evaluated-command-stage-arguments stage))
              (nshell.domain.parsing:ast-node-span command-node))))
         (terminal-redirect-kind (redirect)
           (case (nshell.domain.parsing:ast-redirect-entry-kind redirect)
             (:input-file :<)
             (:output-file :>)
             (:append-output-file :>>)
             (:force-output-file :>)
             (:error-file :2>)
             (:append-error-file :2>>)
             (:both-output-files :&>)
             (:append-both-output-files :&>>)
             (:here-document :<<)
             (:here-document-strip-tabs :<<-)
             (:here-string :<<<)
             ((:duplicate-input-fd :duplicate-output-fd) :fd-dup)))
         (terminal-redirect-supported-p (redirect)
           (let ((kind
                   (nshell.domain.parsing:ast-redirect-entry-kind redirect))
                 (descriptor
                   (nshell.domain.parsing:ast-redirect-entry-file-descriptor
                    redirect))
                 (target
                   (nshell.domain.parsing:ast-redirect-entry-target redirect)))
             (case kind
               (:input-file (= (or descriptor 0) 0))
               (:here-document (= (or descriptor 0) 0))
               (:here-document-strip-tabs (= (or descriptor 0) 0))
               (:here-string (= (or descriptor 0) 0))
               ((:output-file :append-output-file :force-output-file)
                (= (or descriptor 1) 1))
               ((:error-file :append-error-file)
                (= (or descriptor 2) 2))
               ((:both-output-files :append-both-output-files) t)
               ((:duplicate-input-fd :duplicate-output-fd)
                (and
                 (integerp
                  (nshell.domain.parsing:ast-redirect-entry-file-descriptor
                   redirect))
                 (<= 0
                     (nshell.domain.parsing:ast-redirect-entry-file-descriptor
                      redirect))
                 (or
                  (nshell.domain.parsing:redirect-fd-close-target-p target)
                  (let ((target-descriptor
                          (nshell.domain.parsing:redirect-fd-target-file-descriptor
                           target)))
                    (and (integerp target-descriptor)
                         (<= 0 target-descriptor))))))
               (otherwise nil))))
         (terminal-redirect (stage redirect)
           (let* ((kind
                    (nshell.domain.parsing:ast-redirect-entry-kind redirect))
                  (target
                    (nshell.domain.parsing:ast-redirect-entry-target redirect))
                  (redirect-target
                    (case kind
                      ((:duplicate-input-fd :duplicate-output-fd)
                       (nshell.domain.parsing:make-redirect-fd-dup-target
                        (nshell.domain.parsing:ast-redirect-entry-file-descriptor
                         redirect)
                        (if (nshell.domain.parsing:redirect-fd-close-target-p
                             target)
                            :close
                            (nshell.domain.parsing:redirect-fd-target-file-descriptor
                             target))
                        (if (eq kind :duplicate-input-fd) :input :output)))
                      ((:here-document :here-document-strip-tabs)
                       (nshell.domain.parsing:redirect-heredoc-target-body
                        target))
                      (otherwise
                       (let ((evaluated-target
                               (%reader-find-evaluated-redirect-target
                                stage redirect)))
                         (unless evaluated-target
                           (%reader-plan-error
                            (nshell.domain.parsing:ast-redirect-entry-source-span
                             redirect)
                            :redirect-target
                            (%reader-simple-condition
                             "Reader redirect target was not evaluated.")))
                         (argv-scalar-string
                          (nshell.domain.parsing:evaluated-command-arg-value
                           evaluated-target)
                          :source-span
                          (nshell.domain.parsing:evaluated-command-arg-source-span
                           evaluated-target)))))))
             (cons (terminal-redirect-kind redirect) redirect-target)))
         (terminal-stage-redirects (stage)
           (loop for redirect in
                   (stable-sort
                    (copy-list
                     (nshell.domain.parsing:command-node-redirects
                      (nshell.application:evaluated-command-stage-command-node
                       stage)))
                    #'<
                    :key #'nshell.domain.parsing:ast-redirect-entry-source-order)
                 collect (terminal-redirect stage redirect))))
    (when (and (or *foreground-terminal-runner*
                    (eq :os-pipes (shell-context-execution-strategy context)))
               (null plans)
               evaluated-stages
               (every
                (lambda (stage)
                  (and
                   (eq :external
                       (nshell.application:evaluated-command-stage-dispatch-kind
                        stage))
                   (null
                    (nshell.application:evaluated-command-stage-environment-assignments
                     stage))
                   (every #'terminal-redirect-supported-p
                          (nshell.domain.parsing:command-node-redirects
                           (nshell.application:evaluated-command-stage-command-node
                            stage)))))
                evaluated-stages)
               (every
                (lambda (edge)
                  (eq :pipe
                      (nshell.domain.parsing:pipeline-edge-kind edge)))
                (%reader-pipeline-edges ast)))
      (let* ((nshell.infrastructure.acl:*exported-environment*
               (%context-exported-environment-strings context))
             (commands (mapcar #'terminal-command evaluated-stages))
             (stage-redirects (mapcar #'terminal-stage-redirects evaluated-stages))
             (redirects (and (some #'identity stage-redirects) stage-redirects)))
        (if (and (not *foreground-terminal-runner*) (eq :os-pipes (shell-context-execution-strategy context)))
            (let ((output nil)
                  (status nil)
                  (stage-statuses nil))
              (setf output
                    (with-output-to-string (stream)
                      (let ((*standard-output* stream))
                        (multiple-value-setq (status stage-statuses)
                          (nshell.infrastructure.acl:spawn-pipeline
                           commands
                           :redirects redirects
                           :pipefail-p (shell-context-pipefail-p context))))))
              (let* ((statuses (or stage-statuses (list status)))
                     (signals (make-list (length statuses) :initial-element nil)))
                (values
                 t output status
                 (make-pipeline-execution-result status statuses signals))))
            (if (and (= 1 (length evaluated-stages))
                     (null (first redirects)))
                (let ((stage (first evaluated-stages))
                      (command-node
                        (nshell.application:evaluated-command-stage-command-node
                         (first evaluated-stages))))
                  (multiple-value-bind (output status)
                      (funcall
                       *foreground-terminal-runner*
                       (lambda ()
                         (%run-terminal-command
                          context
                          (nshell.domain.parsing:command-node-command command-node)
                          (command-argv-strings
                           context
                           (nshell.application:evaluated-command-stage-arguments
                            stage)))))
                    (values
                     t output status
                     (make-pipeline-execution-result status (list status) (list nil)))))
                (multiple-value-bind (output status stage-statuses)
                    (funcall
                     *foreground-terminal-runner*
                     (lambda ()
                       (%run-terminal-pipeline context commands redirects)))
                  (let* ((statuses (or stage-statuses (list status)))
                         (signals (make-list (length statuses) :initial-element nil)))
                    (values
                     t output status
                     (make-pipeline-execution-result status statuses signals))))))))))
(defun %reader-process-substitution-form (entry)
  (nshell.domain.parsing:redirect-procsub-target-form
   (nshell.domain.parsing:ast-redirect-entry-target entry)))

(defun %reader-evaluate-process-substitutions
    (context plans stage-evaluator)
  (mapcar
   (lambda (plan)
     (destructuring-bind (stage-index entry commands) plan
       (list stage-index entry
             (%reader-process-substitution-form entry)
             (%reader-evaluate-stages context commands stage-evaluator))))
   plans))

(defun %reader-allocate-process-substitutions (state stages plans)
  (mapcar
   (lambda (plan)
     (destructuring-bind (stage-index entry form evaluated-stages) plan
       (declare (ignore form evaluated-stages))
       (let* ((target
                (nshell.domain.parsing:ast-redirect-entry-target entry))
              (direction
                (nshell.domain.parsing:redirect-procsub-target-direction
                 target))
              (kind
                (nshell.domain.parsing:ast-redirect-entry-kind entry))
              (source-span
                (nshell.domain.parsing:ast-redirect-entry-source-span entry))
              (avoid
                (if (member kind
                            '(:process-substitution-input
                              :process-substitution-output))
                    (append
                     (%reader-redirect-destination-descriptors
                      (nth stage-index stages))
                     '(0 1 2))
                    '(0 1 2)))
              (resource
                (%reader-allocate-with-plan-error
                 source-span
                 (lambda ()
                   (nshell.infrastructure.acl::make-reader-process-substitution-resource
                    direction :avoid-descriptors avoid))))
              (substitution
                (progn
                  (%reader-own-descriptor
                   state
                   (nshell.infrastructure.acl::reader-process-substitution-resource-parent-fd
                    resource)
                   source-span)
                  (%reader-own-descriptor
                   state
                   (nshell.infrastructure.acl::reader-process-substitution-resource-inner-fd
                    resource)
                   source-span)
                  (%reader-register-process-substitution
                   state stage-index entry resource))))
         (list stage-index entry
               (%reader-process-substitution-form entry)
               (fourth plan) substitution))))
   plans))

(defun %reader-close-process-substitution-inner (state substitution)
  (let* ((resource
           (%reader-process-substitution-resource substitution))
         (fd
           (nshell.infrastructure.acl::reader-process-substitution-resource-inner-fd
            resource)))
    (when fd
      (%reader-close-owned-descriptor state fd)
      (setf (nshell.infrastructure.acl::reader-process-substitution-resource-inner-fd
             resource)
            nil))))

(defun %reader-start-process-substitutions (context state plans)
  (dolist (plan plans)
    (destructuring-bind
        (stage-index entry form evaluated-stages substitution)
        plan
      (let* ((resource
               (%reader-process-substitution-resource substitution))
             (direction
               (nshell.infrastructure.acl::reader-process-substitution-resource-direction
                resource))
             (inner-fd
               (nshell.infrastructure.acl::reader-process-substitution-resource-inner-fd
                resource))
             (before
               (copy-list (%reader-execution-state-descriptors state)))
             (bindings
               (%reader-build-stage-bindings
                context state form evaluated-stages
                :input-fd (and (eq direction :output) inner-fd)
                :output-fd (and (eq direction :input) inner-fd)))
             (stage-io
               (%reader-stage-io-list bindings state nil))
             (handle
               (handler-case
                   (spawn-byte-stream-node-in-context
                    context evaluated-stages stage-io
                    #'%reader-dispatch-internal-stage)
                 (byte-stream-execution-error (condition)
                   (%reader-plan-error
                    (nshell.domain.parsing:ast-redirect-entry-source-span
                     entry)
                    :start condition)))))
        (setf (%reader-process-substitution-handle substitution) handle)
        (dolist (fd
                 (set-difference
                  (%reader-execution-state-descriptors state)
                  before :test #'eql))
          (%reader-close-owned-descriptor state fd))
        (%reader-close-process-substitution-inner state substitution))))
  plans)

(defun %reader-wait-process-substitutions (state)
  (dolist (substitution
           (reverse (%reader-execution-state-process-substitutions state)))
    (let ((handle (%reader-process-substitution-handle substitution)))
      (when handle
        (handler-case
            (wait-byte-stream-execution handle)
          (byte-stream-execution-error (condition)
            (setf (%reader-process-substitution-handle substitution) nil)
            (%reader-plan-error
             (nshell.domain.parsing:ast-redirect-entry-source-span
              (%reader-process-substitution-entry substitution))
             (byte-stream-execution-error-operation condition)
             condition)))
        (setf (%reader-process-substitution-handle substitution) nil))))
  nil)

(defun %reader-execute-foreground-in-context
    (context ast stage-evaluator)
  (when (and (nshell.domain.parsing:command-node-p ast)
             (string= "" (nshell.domain.parsing:command-node-command ast))
             (nshell.domain.parsing:command-node-environment-assignments ast))
    (let ((assignments
            (mapcar (lambda (assignment)
                      (%assignment-word-binding
                       context
                       (nshell.domain.parsing:command-arg-value assignment)))
                    (nshell.domain.parsing:command-node-environment-assignments
                     ast))))
      (%assign-shell-variables context assignments)
      (%record-pipeline-statuses context '(0))
      (%record-last-exit-code context 0)
      (return-from %reader-execute-foreground-in-context
        (values nil 0 (make-pipeline-execution-result 0 '(0) '(nil))))))
  (let ((state (%make-reader-execution-state)))
    (unwind-protect
         (let* ((commands (%reader-command-stages ast))
                (span (nshell.domain.parsing:ast-node-span ast)))
           (unless commands
             (%reader-plan-error
              span :dispatch
              (%reader-simple-condition
               "Reader command or pipeline has no command stages.")))
           (let* ((plans
                    (%reader-preflight-process-substitutions context commands))
                  (evaluated-stages
                    (%reader-evaluate-stages
                     context commands stage-evaluator))
                  (evaluated-substitutions
                    (multiple-value-bind (terminal-p output status result)
                        (%reader-terminal-external-dispatch
                         context ast plans evaluated-stages)
                      (when terminal-p
                        (%record-pipeline-statuses
                         context
                         (pipeline-execution-result-stage-statuses result))
                        (return-from %reader-execute-foreground-in-context
                          (values output status result)))
                      (%reader-evaluate-process-substitutions
                       context plans stage-evaluator)))
                  (substitutions
                    (%reader-allocate-process-substitutions
                     state commands evaluated-substitutions))
                  (evaluated-stages
                    (loop for stage in evaluated-stages
                          for index from 0
                          collect
                          (%reader-rewrite-process-substitution-arguments
                           state index stage))))
             (%reader-start-process-substitutions
              context state substitutions)
             (let* ((bindings
                      (%reader-build-stage-bindings
                       context state ast evaluated-stages))
                    (stage-io
                      (%reader-stage-io-list bindings state))
                    (single-stage-result
                      (%reader-run-single-internal-stage
                       context evaluated-stages stage-io))
                    (handle
                      (unless single-stage-result
                        (handler-case
                            (spawn-byte-stream-node-in-context
                             context evaluated-stages stage-io
                             #'%reader-dispatch-internal-stage)
                          (byte-stream-execution-error (condition)
                            (%reader-plan-error
                             span
                             (byte-stream-execution-error-operation condition)
                             condition)))))
                    (keep
                      (mapcar
                       (lambda (substitution)
                         (nshell.infrastructure.acl::reader-process-substitution-resource-parent-fd
                          (%reader-process-substitution-resource substitution)))
                       (%reader-execution-state-process-substitutions state))))
               (%reader-close-owned-descriptors state keep)
               (let ((result
                       (or single-stage-result
                           (handler-case
                               (wait-byte-stream-execution handle)
                             (byte-stream-execution-error (condition)
                               (%reader-plan-error
                                span
                                (byte-stream-execution-error-operation condition)
                                condition))))))
                 (%reader-close-owned-descriptors state)
                 (%reader-wait-process-substitutions state)
                 (%record-pipeline-statuses
                  context
                  (pipeline-execution-result-stage-statuses result))
                 (values nil
                         (pipeline-execution-result-status result)
                         result)))))
      (%reader-cleanup-execution-state state))))

(defun %reader-background-unsupported (ast message &optional source-span)
  (%reader-plan-error
   (or source-span
       (and (nshell.domain.parsing::ast-node-p ast)
            (nshell.domain.parsing:ast-node-span ast)))
   :background
   (%reader-simple-condition "~a" message)))

(defun %reader-background-command (context evaluated-stage)
  (let* ((command
           (nshell.application:evaluated-command-stage-command-node
            evaluated-stage))
         (arguments
           (command-argv-strings
            context
            (nshell.application:evaluated-command-stage-arguments
             evaluated-stage))))
    (nshell.domain.parsing:make-command-node
     (nshell.domain.parsing:command-node-command command)
     (mapcar #'nshell.domain.parsing:make-command-arg arguments)
     (nshell.domain.parsing:ast-node-span command))))

(defun %reader-spawn-background-node-in-context
    (context ast stage-evaluator)
  (let ((commands (%reader-command-stages ast)))
    (unless commands
      (%reader-background-unsupported
       ast "Background execution requires a command or pipeline."))
    (dolist (command commands)
      (dolist (entry
               (nshell.domain.parsing:command-node-redirects command))
        (when (nshell.domain.parsing:redirect-procsub-target-p
               (nshell.domain.parsing:ast-redirect-entry-target entry))
          (%reader-background-unsupported
           ast "Process substitution is not supported in background execution."
           (nshell.domain.parsing:ast-redirect-entry-source-span entry)))))
    (unless (every (lambda (command)
                     (and
                      (null
                       (nshell.domain.parsing:command-node-redirects command))
                      (null
                       (nshell.domain.parsing:command-node-environment-assignments
                        command))))
                   commands)
      (%reader-background-unsupported
       ast
       "Background execution supports only external commands without redirects or environment assignments."))
    (when (and (nshell.domain.parsing:pipeline-node-p ast)
               (some (lambda (edge)
                       (not (eq :pipe
                                (nshell.domain.parsing:pipeline-edge-kind
                                 edge))))
                     (%reader-pipeline-edges ast)))
      (%reader-background-unsupported
       ast "Background pipelines support only ordinary pipe edges."))
    (dolist (command commands)
      (unless (command-node-external-p context command)
        (%reader-background-unsupported
         ast "Background execution requires external command stages.")))
    (let* ((evaluated-stages
             (%reader-evaluate-stages context commands stage-evaluator))
           (background-commands
             (loop for stage in evaluated-stages
                   for command in commands
                   unless (eq :external
                              (nshell.application:evaluated-command-stage-dispatch-kind
                               stage))
                     do (%reader-background-unsupported
                         ast "Background execution requires external command stages."
                         (nshell.domain.parsing:ast-node-span command))
                   collect (%reader-background-command context stage)))
           (command-line (nshell.domain.parsing:ast-node->command-line ast))
           (processes
             (if (= (length background-commands) 1)
                 (let* ((command (first background-commands))
                        (process
                          (nshell.infrastructure.acl:spawn-async
                           (nshell.domain.parsing:command-node-command command)
                           (nshell.domain.parsing:command-node-arg-values
                            command))))
                   process)
                 (nshell.infrastructure.acl:spawn-pipeline-async
                  background-commands))))
      (unless processes
        (return-from %reader-spawn-background-node-in-context
          (values nil 127
                  (make-pipeline-execution-result 127 nil nil))))
      (%register-background-job context processes command-line)
      (values nil 0 (make-pipeline-execution-result 0 nil nil)))))

