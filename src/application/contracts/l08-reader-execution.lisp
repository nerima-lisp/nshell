(in-package #:nshell.application)

(define-condition command-execution-plan-error (error)
  ((source-span :initarg :source-span
                :reader command-execution-plan-error-source-span)
   (operation :initarg :operation
              :reader command-execution-plan-error-operation)
   (cause :initarg :cause :reader command-execution-plan-error-cause)))

(declaim
  (ftype
   (function (t t function &optional function)
    (values t integer pipeline-execution-result))
   execute-reader-ast-in-context))
(defun execute-reader-ast-in-context
    (context ast stage-evaluator &optional command-failure-policy)
  (cond
    ((nshell.domain.parsing:sequence-node-p ast)
     (%execute-reader-sequence-node-in-context
      context ast stage-evaluator command-failure-policy))
    ((or (nshell.domain.parsing:command-node-p ast)
         (nshell.domain.parsing:pipeline-node-p ast))
     (%reader-execute-foreground-in-context context ast stage-evaluator))
    (t
     (error 'command-execution-plan-error
            :source-span
            (and (nshell.domain.parsing::ast-node-p ast)
                 (nshell.domain.parsing:ast-node-span ast))
            :operation :dispatch
            :cause
            (make-condition 'simple-error
                            :format-control "Unsupported reader AST node."
                            :format-arguments nil)))))

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
                       (unless (command-node-external-p context inner-command)
                         (%reader-plan-error
                          (nshell.domain.parsing:ast-redirect-entry-source-span
                           entry)
                          :preflight
                          (%reader-simple-condition
                           "Process substitution requires external stages."))))
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
   (nshell.application:evaluated-command-stage-redirect-target-values stage)))

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

(defun %reader-stage-io-list (bindings state)
  (loop for stage-bindings in bindings
        for stage-index from 0
        collect
        (make-pipeline-stage-io
         (%reader-binding-alist stage-bindings)
         (loop for substitution
               in (%reader-execution-state-process-substitutions state)
               when (= stage-index
                       (%reader-process-substitution-stage-index
                        substitution))
                 collect
                 (nshell.infrastructure.acl::reader-process-substitution-resource-parent-fd
                  (%reader-process-substitution-resource
                   substitution))))))

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
    (context evaluated-stage stage-io argv-strings)
  (let* ((binding
           (nshell.application:evaluated-command-stage-binding
            evaluated-stage))
         (dispatch-kind
           (nshell.application:evaluated-command-stage-dispatch-kind
            evaluated-stage))
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
         (when output
           (write-string output *standard-output*))
         (values status nil)))
      (:shell-function
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
                   (command-failed-signal condition))))))))

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
               (%reader-stage-io-list bindings state))
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
                    (%reader-evaluate-process-substitutions
                     context plans stage-evaluator))
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
                    (handle
                      (handler-case
                          (spawn-byte-stream-node-in-context
                           context evaluated-stages stage-io
                           #'%reader-dispatch-internal-stage)
                        (byte-stream-execution-error (condition)
                          (%reader-plan-error
                           span
                           (byte-stream-execution-error-operation condition)
                           condition))))
                    (keep
                      (mapcar
                       (lambda (substitution)
                         (nshell.infrastructure.acl::reader-process-substitution-resource-parent-fd
                          (%reader-process-substitution-resource substitution)))
                       (%reader-execution-state-process-substitutions state))))
               (%reader-close-owned-descriptors state keep)
               (let ((result
                       (handler-case
                           (wait-byte-stream-execution handle)
                         (byte-stream-execution-error (condition)
                           (%reader-plan-error
                            span
                            (byte-stream-execution-error-operation condition)
                            condition)))))
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

