(in-package #:nshell.application)

(defun %read-stream-to-string (stream)
  (with-output-to-string (out)
    (loop for char = (read-char stream nil nil)
          while char
          do (write-char char out))))

(defun %make-pipeline-shell-context ()
  (make-shell-context
   :environment (nshell.domain.environment:inject-os-environment
                 (nshell.domain.environment:make-default-environment))))

(defun execute-command-line (line history dispatcher)
  (nshell.domain.parsing:with-complete-command-line (result ast line)
    (when dispatcher
      (publish-event dispatcher
                     (nshell.domain.events:make-command-entered-event line)))
    (nshell.domain.history:history-add history line)
    (when dispatcher
      (publish-event dispatcher
                     (nshell.domain.events:make-command-appended-to-history-event line)))
    (when dispatcher
      (publish-event dispatcher
                     (nshell.domain.events:make-command-parsed-event ast)))
    (values ast result)))

(defun %expand-source-arg (arg &optional environment)
  (let ((value (nshell.domain.parsing:arg-value arg)))
    (nshell.domain.expansion:expand-by-quote-style
     (nshell.domain.parsing:arg-quote-style arg)
     (if environment
         (nshell.domain.expansion:expand-all value environment)
         (list value))
     (list value)
     (if environment
         (list (nshell.domain.expansion:expand-double-quoted value environment))
         (list value)))))

(defun %expand-unquoted-source-arg-in-context (context value environment)
  (multiple-value-bind (fields argv-reference-p)
      (nshell.domain.expansion:argv-reference-fields value)
    (if argv-reference-p
        fields
        (loop for expanded in (%expand-command-substitutions context value)
              append (nshell.domain.expansion:expand-all expanded environment)))))

(defun %expand-double-quoted-source-arg-in-context (context value environment)
  (list (apply #'concatenate 'string
               (loop for expanded in (%expand-command-substitutions context value)
                     collect (nshell.domain.expansion:expand-double-quoted
                              expanded environment)))))

(defun %trim-command-substitution-output (output)
  (let* ((text (or output ""))
         (end (length text)))
    (loop while (and (> end 0)
                     (member (char text (1- end)) '(#\Newline #\Return)))
          do (decf end))
    (subseq text 0 end)))

(defun %command-substitution-fields (output)
  (let ((text (%trim-command-substitution-output output))
        (fields nil)
        (start 0))
    (unless (string= text "")
      (loop for newline = (position #\Newline text :start start)
            do (push (subseq text start newline) fields)
            if newline
              do (setf start (1+ newline))
            else
              do (return)))
    (nreverse fields)))

(defun %append-command-substitution-char (parts ch)
  (mapcar (lambda (part)
            (concatenate 'string part (string ch)))
          parts))

(defun %append-command-substitution-fields (parts fields)
  (let ((result nil)
        (values (or fields '(""))))
    (dolist (part parts (nreverse result))
      (dolist (field values)
        (push (concatenate 'string part field) result)))))

(defun %append-command-substitution-string (parts string)
  (mapcar (lambda (part) (concatenate 'string part string)) parts))

(defun %paren-balanced-end (value start)
  "VALUE/START point at an opening #\(. Return the index just past the paren that
returns depth to zero, or NIL when unbalanced."
  (let ((depth 0))
    (loop for index from start below (length value)
          for ch = (char value index)
          do (cond ((char= ch #\() (incf depth))
                   ((char= ch #\)) (decf depth)
                    (when (zerop depth) (return (1+ index))))))))

(defun %command-sub-fields-at (context value open-paren)
  "Run the command substitution whose opening #\( is at OPEN-PAREN and return
its output fields, or NIL when the parens are empty/unbalanced."
  (let ((end (nshell.domain.parsing::%balanced-substitution-end value open-paren)))
    (when (and end (> end (1+ open-paren)))
      (values (%execute-command-substitution-fields
               context (subseq value (1+ open-paren) end))
              (1+ end)))))

(defun %expand-arithmetic-command-substitution-at (value pos parts len)
  (if (and (char= (char value pos) #\$)
           (< (+ pos 2) len)
           (char= (char value (1+ pos)) #\()
           (char= (char value (+ pos 2)) #\())
      (let ((end (%paren-balanced-end value (1+ pos))))
        (if end
            (values (%append-command-substitution-string
                     parts (subseq value pos end))
                    end)
            (values (%append-command-substitution-char parts #\$)
                    (1+ pos))))
      (values nil nil)))

(defun %expand-posix-command-substitution-at (context value pos parts len)
  (if (and (char= (char value pos) #\$)
           (< (1+ pos) len)
           (char= (char value (1+ pos)) #\())
      (multiple-value-bind (fields next)
          (%command-sub-fields-at context value (1+ pos))
        (if next
            (values (%append-command-substitution-fields parts fields)
                    next)
            (values (%append-command-substitution-char parts #\$)
                    (1+ pos))))
      (values nil nil)))

(defun %expand-bare-command-substitution-at (context value pos parts)
  (if (char= (char value pos) #\()
      (multiple-value-bind (fields next)
          (%command-sub-fields-at context value pos)
        (if next
            (values (%append-command-substitution-fields parts fields)
                    next)
            (values (%append-command-substitution-char parts #\()
                    (1+ pos))))
      (values nil nil)))

(defun %expand-command-substitution-at (context value pos parts len)
  (multiple-value-bind (next-parts next-pos)
      (%expand-arithmetic-command-substitution-at value pos parts len)
    (if next-pos
        (values next-parts next-pos)
        (multiple-value-bind (next-parts next-pos)
            (%expand-posix-command-substitution-at context value pos parts len)
          (if next-pos
              (values next-parts next-pos)
              (multiple-value-bind (next-parts next-pos)
                  (%expand-bare-command-substitution-at context value pos parts)
                (if next-pos
                    (values next-parts next-pos)
                    (values (%append-command-substitution-char parts (char value pos))
                            (1+ pos)))))))))

(defun %walk-command-substitutions (context value pos parts len)
  (if (>= pos len)
      parts
      (multiple-value-bind (next-parts next-pos)
          (%expand-command-substitution-at context value pos parts len)
        (%walk-command-substitutions context value next-pos next-parts len))))

(defun %expand-command-substitutions (context value)
  "Expand command substitutions in VALUE: fish-style (cmd) and POSIX $(cmd).
Arithmetic $((expr)) is passed through untouched so the arithmetic expander can
handle it later."
  (%walk-command-substitutions context value 0 (list "") (length value)))

(defun %expand-source-arg-in-context (context arg)
  (let ((value (nshell.domain.parsing:arg-value arg))
        (environment (shell-context-environment context)))
    (nshell.domain.expansion:expand-by-quote-style
     (nshell.domain.parsing:arg-quote-style arg)
     (%expand-unquoted-source-arg-in-context context value environment)
     (list value)
     (%expand-double-quoted-source-arg-in-context context value environment))))

(defun %line-command-args (command-node &optional environment)
  (loop for arg in (nshell.domain.parsing:command-node-args command-node)
        append (%expand-source-arg arg environment)))

(defun %line-command-args-in-context (context command-node)
  (%line-command-args command-node (shell-context-environment context)))

(defun execute-pipeline (pipeline-ast)
  "Execute a pipeline AST using OS-level pipes through the infrastructure layer."
  (let ((commands (if (nshell.domain.parsing:pipeline-node-p pipeline-ast)
                      (nshell.domain.parsing:pipeline-node-commands pipeline-ast)
                      (list pipeline-ast))))
    (multiple-value-bind (expanded-commands error)
        (%expand-command-nodes-in-context (%make-pipeline-shell-context) commands)
      (when error
        (write-string error *error-output*)
        (return-from execute-pipeline 127))
      (multiple-value-bind (clean-commands redirects)
          (%extract-pipeline-redirects expanded-commands)
        (nshell.infrastructure.acl:spawn-pipeline clean-commands
                                                  :redirects redirects)))))

(defun execute-pipeline-use-case (pipeline dispatcher)
  (when dispatcher
    (publish-event dispatcher
                   (nshell.domain.events:make-pipeline-started-event pipeline nil)))
  (let ((exit-code (or (execute-pipeline pipeline) 0)))
    (when dispatcher
      (publish-event dispatcher
                     (nshell.domain.events:make-pipeline-completed-event pipeline exit-code)))
    exit-code))

(defun %extract-command-redirects (cmd-node)
  (let ((clean nil)
        (redirects nil)
        (args (nshell.domain.parsing:command-node-args cmd-node)))
    (loop with index = 0
          with limit = (length args)
          while (< index limit)
          for arg = (nth index args)
          for value = (nshell.domain.parsing:arg-value arg)
          for spec = (assoc value nshell.domain.parsing:+redirect-specs+ :test #'string=)
          do (cond
               ;; fd-dup redirects (e.g. 2>&1) take no following file target.
               ((and spec (member (cdr spec) nshell.domain.parsing:+redirect-fd-dup-specs+))
                (push (cons (cdr spec) nil) redirects)
                (incf index))
               ((and spec (< (1+ index) limit))
                (let ((target (nshell.domain.parsing:arg-value (nth (1+ index) args))))
                  (push (cons (cdr spec) target) redirects)
                  (incf index 2)))
               (t
                (push arg clean)
                (incf index))))
    (values (nshell.domain.parsing:make-command-node
             (nshell.domain.parsing:command-node-command cmd-node)
             (nreverse clean))
            (nreverse redirects))))

(defun %extract-pipeline-redirects (commands)
  (let ((clean-commands nil)
        (redirects nil))
    (dolist (command commands)
      (multiple-value-bind (clean-command command-redirects)
          (%extract-command-redirects command)
        (push clean-command clean-commands)
        (push command-redirects redirects)))
    (values (nreverse clean-commands) (nreverse redirects))))

(defun %input-redirect-spec (redirects)
  (find-if (lambda (redirect)
             (member (car redirect) '(:< :<< :<<<)))
           redirects
           :from-end t))

(defun %input-redirect-target (redirects)
  (let ((redirect (%input-redirect-spec redirects)))
    (when (and redirect (eq (car redirect) :<))
      (cdr redirect))))

(defun %input-redirect-string (redirects)
  (let ((redirect (%input-redirect-spec redirects)))
    (cond
      ((and redirect (eq (car redirect) :<<<))
       (values (cdr redirect) t))
      ((and redirect (eq (car redirect) :<<))
       (values (cdr redirect) nil)))))

(defun %output-redirect-spec (redirects)
  (let ((redirect (find-if (lambda (redirect)
                             (member (car redirect) '(:> :>> :&> :&>>)))
                           redirects
                           :from-end t)))
    (when redirect
      (values (cdr redirect)
              (if (member (car redirect) '(:>> :&>>)) :append :supersede)))))

(defun %write-redirected-stage-output (redirects output)
  (multiple-value-bind (target mode)
      (%output-redirect-spec redirects)
    (when target
      (with-open-file (stream target
                              :direction :output
                              :if-exists mode
                              :if-does-not-exist :create)
        (write-string (or output "") stream))
      t)))

(defun %pipeline-stderr-spec (redirects)
  "Return (values KIND TARGET MODE) for stderr in a pipeline stage: :MERGE (into
stdout), :FILE with TARGET/MODE, or NIL when stderr is not redirected."
  (let ((redirect (find-if (lambda (r)
                             (member (car r) '(:2> :2>> :2>&1 :&> :&>>)))
                           redirects :from-end t)))
    (when redirect
      (case (car redirect)
        (:2>&1 (values :merge nil nil))
        (:2>   (values :file (cdr redirect) :supersede))
        (:2>>  (values :file (cdr redirect) :append))
        (:&>   (values :file (cdr redirect) :supersede))
        (:&>>  (values :file (cdr redirect) :append))))))

(defun %execute-external-pipeline-stage (command-node input redirects)
  (let* ((command (nshell.domain.parsing:command-node-command command-node))
         (args (%line-command-args command-node))
         (input-target (%input-redirect-target redirects))
         (opened-input nil)
         (stdin (cond
                  (input-target
                   (setf opened-input
                         (open input-target
                               :direction :input
                               :if-does-not-exist :error)))
                  (input (make-string-input-stream input))
                  (t *standard-input*))))
    (multiple-value-bind (stderr-kind stderr-target stderr-mode)
        (%pipeline-stderr-spec redirects)
      (handler-case
          (unwind-protect
               (let ((process
                       (sb-ext:run-program command args
                                           :input stdin
                                           :output :stream
                                           ;; Default and 2>&1 keep stderr merged
                                           ;; into the captured stdout; a file
                                           ;; redirect captures stderr separately.
                                           :error (if (eq stderr-kind :file) :stream :output)
                                           :wait nil
                                           :search t)))
                 (let ((output (%read-stream-to-string (sb-ext:process-output process)))
                       (errout (when (eq stderr-kind :file)
                                 (%read-stream-to-string (sb-ext:process-error process))))
                       (stdout-target (%output-redirect-spec redirects)))
                   (sb-ext:process-wait process)
                   (let ((stdout-written (%write-redirected-stage-output redirects output)))
                     (when (eq stderr-kind :file)
                       ;; When stderr shares the stdout file (&>), append after
                       ;; the stdout content rather than truncating it.
                       (let ((mode (if (and stdout-target (equal stderr-target stdout-target))
                                       :append
                                       stderr-mode)))
                         (with-open-file (stream stderr-target
                                                 :direction :output
                                                 :if-exists mode
                                                 :if-does-not-exist :create)
                           (write-string (or errout "") stream))))
                     (values (and (not stdout-written) output)
                             (or (sb-ext:process-exit-code process) 0)))))
            (when opened-input
              (close opened-input)))
        (error (condition)
          (values (format nil "nshell: ~a: ~a~%" command condition) 127))))))

(defun %execute-pipeline-stage-in-context (context command-node input redirects)
  (if (%shell-internal-command-p context command-node)
      (if input
          (with-input-from-string (*standard-input* input)
            (%execute-clean-command-node-in-context context command-node redirects))
          (%execute-clean-command-node-in-context context command-node redirects))
      (%execute-external-pipeline-stage command-node input redirects)))

(defun %expand-command-node-in-context (context command-node)
  (let ((expanded-command (expand-command-alias-node
                           command-node
                           (shell-context-alias-table context))))
    (nshell.domain.parsing:make-command-node
     (nshell.domain.parsing:command-node-command expanded-command)
     (%line-command-args-in-context context expanded-command))))

(defun %expand-command-nodes-in-context (context commands)
  (mapcar (lambda (command)
            (%expand-command-node-in-context context command))
          commands))

(defun %execute-source-pipeline-in-context (context commands redirects)
  (let ((input nil)
        (code 0))
    (loop for command in commands
          for command-redirects in redirects
          do
      (multiple-value-bind (output exit-code)
          (%execute-pipeline-stage-in-context context command input command-redirects)
        (setf input output
              code (or exit-code 0))))
    (values input code)))

(defun execute-pipeline-node-in-context (context pipeline-node)
  (let ((commands (nshell.domain.parsing:pipeline-node-commands pipeline-node)))
    (multiple-value-bind (clean-commands redirects)
        (%extract-pipeline-redirects
         (%expand-command-nodes-in-context context commands))
      (if (or (eq :cps (shell-context-execution-strategy context))
              (some (lambda (command)
                      (%shell-internal-command-p context command))
                    clean-commands))
          (%execute-source-pipeline-in-context context clean-commands redirects)
          (let ((exit-code 0))
            (let ((output
                    (with-output-to-string (*standard-output*)
                      (setf exit-code
                            (or (nshell.infrastructure.acl:spawn-pipeline
                                 clean-commands
                                 :redirects redirects)
                                0)))))
              (values output exit-code)))))))

(defun %redirect-fn (context key)
  (getf (shell-context-redirect-fns context) key))

(defun %output-redirect-p (redirects)
  (find-if (lambda (redirect)
             (member (car redirect) '(:> :>> :&> :&>>)))
           redirects))

(defun %apply-context-redirects (context redirects)
  (dolist (redirect redirects)
    (let ((target (cdr redirect)))
      (case (car redirect)
        (:> (funcall (%redirect-fn context :redirect-output) target :supersede))
        (:>> (funcall (%redirect-fn context :redirect-output) target :append))
        ;; &> / &>> : stdout to the file; stderr follows via the default
        ;; merge-into-stdout behavior in the process adapters.
        (:&> (funcall (%redirect-fn context :redirect-output) target :supersede))
        (:&>> (funcall (%redirect-fn context :redirect-output) target :append))
        ;; 2> / 2>> : stderr to its own file.
        (:2> (let ((fn (%redirect-fn context :redirect-error)))
               (when fn (funcall fn target :supersede))))
        (:2>> (let ((fn (%redirect-fn context :redirect-error)))
                (when fn (funcall fn target :append))))
        (:< (funcall (%redirect-fn context :redirect-input) target))
        ;; 2>&1 is the default (stderr merged into stdout); nothing to apply.
        (t nil)))))

(defun %restore-context-redirects (context)
  (let ((restore (%redirect-fn context :restore)))
    (when restore
      (funcall restore))))

(defun %execute-clean-command-node-in-context (context clean-command redirects)
  (let* ((command (nshell.domain.parsing:command-node-command clean-command))
         (args (%line-command-args clean-command))
         (redirect-output-p (%output-redirect-p redirects)))
    (unwind-protect
         (progn
           (when redirects
             (%apply-context-redirects context redirects))
           (multiple-value-bind (output code)
               (%execute-command-by-name-in-context context command args)
             (when (and redirect-output-p output)
               (write-string output))
             (values (and (not redirect-output-p) output) code)))
      (when redirects
        (%restore-context-redirects context)))))

(defun execute-command-node-in-context (context command-node)
  (multiple-value-bind (clean-command redirects)
      (%extract-command-redirects
       (%expand-command-node-in-context context command-node))
    (%execute-clean-command-node-in-context context clean-command redirects)))

(defun %shell-internal-command-p (context command-node)
  (let ((command (nshell.domain.parsing:command-node-command command-node)))
    (or (lookup-builtin command)
        (nth-value 1 (gethash command (shell-context-function-table context))))))

(defmacro %with-output-code-accumulator ((output code) &body body)
  `(let ((,output nil)
         (,code 0))
     ,@body
     (values (apply #'concatenate 'string (nreverse ,output)) ,code)))

(defmacro %collect-execution-result ((output code) form &optional (code-value 'exit-code))
  `(multiple-value-bind (chunk exit-code)
       ,form
     (when chunk
       (push chunk ,output))
     (setf ,code ,code-value)))

(defun %execute-condition-in-context (context condition)
  (if condition
      (execute-ast-in-context context condition)
      (values nil 1)))

(defun %execute-ast-list-in-context (context nodes)
  (%with-output-code-accumulator (output code)
    (dolist (node nodes)
      (%collect-execution-result
       (output code)
       (execute-ast-in-context context node)
       (or exit-code 0)))))

(defun %execute-if-node-in-context (context ast)
  (multiple-value-bind (condition-output condition-code)
      (%execute-condition-in-context
       context
       (nshell.domain.parsing:if-node-condition ast))
    (declare (ignore condition-output))
    (cond
      ((= 0 condition-code)
       (%execute-ast-list-in-context
        context
        (nshell.domain.parsing:if-node-then-branch ast)))
      ((nshell.domain.parsing:if-node-else-branch ast)
       (%execute-ast-list-in-context
        context
        (nshell.domain.parsing:if-node-else-branch ast)))
      (t (values nil 0)))))

(defun %execute-for-node-in-context (context ast)
  (%with-output-code-accumulator (output code)
    (dolist (value (loop for value-arg in (nshell.domain.parsing:for-node-in-values ast)
                         append (%expand-source-arg-in-context
                                 context
                                 value-arg)))
      (setf (shell-context-environment context)
            (nshell.domain.environment:env-set
             (shell-context-environment context)
             (nshell.domain.parsing:for-node-var-name ast)
             value
             nil))
      (%collect-execution-result
       (output code)
       (%execute-ast-list-in-context
        context
        (nshell.domain.parsing:for-node-body ast))))))

(defun %execute-while-node-in-context (context ast)
  (%with-output-code-accumulator (output code)
    (loop
      (multiple-value-bind (condition-output condition-code)
          (%execute-condition-in-context
           context
           (nshell.domain.parsing:while-node-condition ast))
        (declare (ignore condition-output))
        (unless (= 0 condition-code)
          (return)))
      (%collect-execution-result
       (output code)
       (%execute-ast-list-in-context
        context
        (nshell.domain.parsing:while-node-body ast))))))

(defun %execute-case-node-in-context (context ast)
  (let* ((raw-value (nshell.domain.parsing:case-node-value ast))
         (expanded (nshell.domain.expansion:expand-all
                    raw-value
                    (shell-context-environment context)))
         (value (or (first expanded) raw-value)))
    (loop for clause in (nshell.domain.parsing:case-node-clauses ast)
          for pattern = (car clause)
          when (or (string= pattern "*") (string= pattern value))
            do (return (%execute-ast-list-in-context context (cdr clause)))
          finally (return (values nil 0)))))

(defun %execute-sequence-node-in-context (context ast)
  (%with-output-code-accumulator (output code)
    (let* ((commands (nshell.domain.parsing:sequence-node-commands ast))
           (separators (nshell.domain.parsing:sequence-node-separators ast)))
      (loop for command in commands
            for index from 0
            for separator = (and (< index (length separators))
                                 (nth index separators))
            do (cond
                 ((eq :amp separator)
                  (%collect-execution-result
                   (output code)
                   (execute-ast-in-context context command)))
                 (t
                  (%collect-execution-result
                   (output code)
                   (execute-ast-in-context context command))
                  (when (or (and (eq :and separator) (/= code 0))
                            (and (eq :or separator) (= code 0)))
                    (return))))))))

(defun execute-ast-in-context (context ast)
  (cond
    ((nshell.domain.parsing:command-node-p ast)
     (execute-command-node-in-context context ast))
    ((nshell.domain.parsing:pipeline-node-p ast)
     (execute-pipeline-node-in-context context ast))
    ((nshell.domain.parsing:if-node-p ast)
     (%execute-if-node-in-context context ast))
    ((nshell.domain.parsing:for-node-p ast)
     (%execute-for-node-in-context context ast))
    ((nshell.domain.parsing:while-node-p ast)
     (%execute-while-node-in-context context ast))
    ((nshell.domain.parsing:case-node-p ast)
     (%execute-case-node-in-context context ast))
    ((nshell.domain.parsing:begin-end-node-p ast)
     (%execute-ast-list-in-context
      context
      (nshell.domain.parsing:begin-end-node-body ast)))
    ((nshell.domain.parsing:sequence-node-p ast)
     (%execute-sequence-node-in-context context ast))
    (t (values (format nil "source: unsupported syntax~%") 2))))
