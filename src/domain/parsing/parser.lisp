(in-package #:nshell.domain.parsing)

(defstruct (%command-list-components
            (:constructor %make-command-list-components
                (commands separators separator-tokens)))
  (commands nil :type list :read-only t)
  (separators nil :type list :read-only t)
  (separator-tokens nil :type list :read-only t))

(defun %command-list-components-from-reduced-entries (entries)
  (%make-command-list-components
   (mapcar #'%reduced-command-entry-command entries)
   (mapcar #'%reduced-command-entry-separator entries)
   (mapcar #'%reduced-command-entry-separator-token entries)))

(defun %last-list-element (items)
  (car (last items)))

(defstruct (%reduced-command-stream
            (:constructor %make-reduced-command-stream
                (commands separators separator-tokens ast)))
  (commands nil :type list :read-only t)
  (separators nil :type list :read-only t)
  (separator-tokens nil :type list :read-only t)
  (ast nil :read-only t))

(defun %reduced-command-stream-from-reducer-entries (reducer-entries)
  (let* ((entries
           (%reduced-command-entries-from-reducer-entries reducer-entries))
         (components
           (%command-list-components-from-reduced-entries entries)))
    (%make-reduced-command-stream
     (%command-list-components-commands components)
     (%command-list-components-separators components)
     (%command-list-components-separator-tokens components)
     (%build-ast-from-reduced-entries entries))))

(defun %reduced-command-stream-last-separator (stream)
  (%last-list-element (%reduced-command-stream-separators stream)))

(defun %reduced-command-stream-last-separator-token (stream)
  (%last-list-element (%reduced-command-stream-separator-tokens stream)))

(defun %continuation-separator-diagnostic (separator token input-length)
  (if token
      (%token-diagnostic
       :trailing-continuation
       (format nil "Expected command after '~a'"
               (%separator-text separator))
       token)
      (%make-parse-diagnostic
       :trailing-continuation
       "Expected command after continuation operator"
       input-length
       input-length)))

(defun %unclosed-control-flow-diagnostic (input-length)
  (%make-parse-diagnostic
   :unclosed-block
   "Expected 'end' to close control-flow block"
   input-length
   input-length))

(defstruct (%structural-diagnostics
            (:constructor %make-structural-diagnostics
                (incomplete-p diagnostics)))
  (incomplete-p nil :type boolean :read-only t)
  (diagnostics nil :type list :read-only t))

(defstruct (%structural-diagnostics-accumulator
            (:constructor %make-structural-diagnostics-accumulator
                (&key (incomplete-p nil) (diagnostics nil))))
  (incomplete-p nil :type boolean)
  (diagnostics nil :type list))

(defun %empty-structural-diagnostics-accumulator ()
  (%make-structural-diagnostics-accumulator))

(defun %structural-diagnostics-accumulator-add-diagnostic
    (accumulator diagnostic &key incomplete-p)
  (push diagnostic
        (%structural-diagnostics-accumulator-diagnostics accumulator))
  (when incomplete-p
    (setf (%structural-diagnostics-accumulator-incomplete-p accumulator) t))
  accumulator)

(defun %structural-diagnostics-from-accumulator (accumulator)
  (%make-structural-diagnostics
   (%structural-diagnostics-accumulator-incomplete-p accumulator)
   (nreverse (%structural-diagnostics-accumulator-diagnostics accumulator))))

(defstruct (%structural-diagnostics-input
            (:constructor %make-structural-diagnostics-input
                (commands last-separator last-separator-token input-length)))
  (commands nil :type list :read-only t)
  (last-separator nil :read-only t)
  (last-separator-token nil :read-only t)
  (input-length 0 :type integer :read-only t))

(defun %structural-diagnostics-input-from-stream (stream input-length)
  (%make-structural-diagnostics-input
   (%reduced-command-stream-commands stream)
   (%reduced-command-stream-last-separator stream)
   (%reduced-command-stream-last-separator-token stream)
   input-length))

(defun %parse-structural-diagnostics-for-input (input)
  (let ((cmds (%structural-diagnostics-input-commands input))
        (last-sep (%structural-diagnostics-input-last-separator input))
        (last-sep-token
          (%structural-diagnostics-input-last-separator-token input))
        (input-length (%structural-diagnostics-input-input-length input))
        (diagnostics (%empty-structural-diagnostics-accumulator)))
    (when (%continuation-separator-p last-sep)
      (%structural-diagnostics-accumulator-add-diagnostic
       diagnostics
       (%continuation-separator-diagnostic
        last-sep last-sep-token input-length)
       :incomplete-p t))
    (when (%unclosed-control-flow-p cmds)
      (%structural-diagnostics-accumulator-add-diagnostic
       diagnostics
       (%unclosed-control-flow-diagnostic input-length)
       :incomplete-p t))
    (dolist (diagnostic (%unexpected-control-flow-diagnostics cmds input-length))
      (%structural-diagnostics-accumulator-add-diagnostic diagnostics
                                                         diagnostic))
    (%structural-diagnostics-from-accumulator diagnostics)))

(defun %parse-result-from-reduced-command-stream (stream errors incomplete input-length)
  (let ((structural-diagnostics
          (%parse-structural-diagnostics-for-input
           (%structural-diagnostics-input-from-stream stream input-length))))
    (%make-normalized-parse-result
     (group-control-flow (%reduced-command-stream-ast stream))
     (nconc (nreverse errors)
            (%structural-diagnostics-diagnostics structural-diagnostics))
     (or incomplete
         (%structural-diagnostics-incomplete-p structural-diagnostics)))))

(defun %parse-result-from-token-reduction-result (reduction incomplete input-length)
  (%parse-result-from-reduced-command-stream
   (%reduced-command-stream-from-reducer-entries
    (%token-reduction-result-commands reduction))
   (%token-reduction-result-errors reduction)
   incomplete
   input-length))

(defun %empty-token-parse-result (incomplete)
  (%make-normalized-parse-result nil nil incomplete))

(defun parse-tokens (tokens incomplete &key (input-length 0))
  (%parse-result-from-token-reduction-result
   (%reduce-token-stream-result tokens)
   incomplete
   input-length))

(defun parse-command-line (input &key (cursor-pos nil))
  (let* ((tokenization (%tokenize-here-doc-aware input cursor-pos))
         (tokens (tokenization-result-tokens tokenization))
         (incomplete (tokenization-result-incomplete-p tokenization)))
    (if (null tokens)
        (%empty-token-parse-result incomplete)
        (parse-tokens tokens incomplete :input-length (length input)))))
