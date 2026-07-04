; Control-flow data layer: constants, frame struct, keyword predicates, diagnostic analysis.
(in-package #:nshell.domain.parsing)

(defparameter +control-flow-keywords+
  '("if" "else" "for" "in" "while" "case" "switch" "begin" "end"))

(defparameter +control-flow-block-keywords+
  '("if" "for" "while" "case" "switch" "begin"))

(defparameter +control-flow-grouper-specs+
  '(("if" . %group-control-flow-if)
    ("for" . %group-control-flow-for)
    ("while" . %group-control-flow-while)
    ("case" . %group-control-flow-case)
    ("switch" . %group-control-flow-switch)
    ("begin" . %group-control-flow-begin)))

(defstruct (control-flow-frame
            (:constructor %make-control-flow-frame (keyword else-seen)))
  (keyword nil :type string :read-only t)
  (else-seen nil :type boolean :read-only t))

(defun control-flow-keyword-p (value)
  (and (stringp value)
       (not (null (member value +control-flow-keywords+ :test #'string=)))))

(defun %command-keyword (node)
  (when (command-node-p node)
    (let ((command (command-node-command node)))
      (and (control-flow-keyword-p command) command))))

(defun %block-opening-keyword-p (keyword)
  (not (null (member keyword +control-flow-block-keywords+ :test #'string=))))

(defstruct (%control-flow-header-args
            (:constructor %make-control-flow-header-args (first rest all)))
  (first nil :read-only t)
  (rest nil :type list :read-only t)
  (all nil :type list :read-only t))

(defun %control-flow-header-args (header)
  (let ((args (and (command-node-p header) (command-node-args header))))
    (%make-control-flow-header-args (first args)
                                    (%copy-ast-list (rest args))
                                    (%copy-ast-list args))))

(defun %command-first-arg-value (header &optional (default ""))
  (let ((arg (%control-flow-header-args-first
              (%control-flow-header-args header))))
    (if arg
        (arg-value arg)
        default)))

(defun %command-from-header-args (header)
  (let* ((header-args (%control-flow-header-args header))
         (arg (%control-flow-header-args-first header-args)))
    (when arg
      (make-command-node (arg-value arg)
                         (%control-flow-header-args-rest header-args)
                         nil
                         (arg-quote-style arg)))))

(defun %else-if-header-p (header)
  (and (command-node-p header)
       (let ((arg (%control-flow-header-args-first
                   (%control-flow-header-args header))))
         (and arg
              (string= "if" (arg-value arg))))))

(defun %consume-control-flow-terminator (nodes keyword)
  (if (and nodes (string= (%command-keyword (first nodes)) keyword))
      (rest nodes)
      nodes))

(defun %stack-top-keyword (stack)
  (let ((top (first stack)))
    (and (control-flow-frame-p top)
         (control-flow-frame-keyword top))))

(defun %case-within-switch-p (keyword stack)
  (and keyword
       (string= keyword "case")
       (string= (%stack-top-keyword stack) "switch")))

(defun %push-control-flow-frame (stack keyword)
  (cons (%make-control-flow-frame keyword nil) stack))

(defun %if-frame-accepts-else-p (frame)
  (and (control-flow-frame-p frame)
       (string= (control-flow-frame-keyword frame) "if")
       (not (control-flow-frame-else-seen frame))))

(defun %control-flow-stack-with-else-seen (stack)
  (let ((frame (first stack)))
    (cons (%make-control-flow-frame (control-flow-frame-keyword frame) t)
          (rest stack))))

(defstruct (%control-flow-stack-transition
            (:constructor %make-control-flow-stack-transition
                (stack unexpected-keyword)))
  (stack nil :type list :read-only t)
  (unexpected-keyword nil :read-only t))

(defun %control-flow-stack-transition (stack cmd)
  (let ((keyword (%command-keyword cmd)))
    (cond
      ((and keyword
            (string= keyword "case")
            (%case-within-switch-p keyword stack))
       (%make-control-flow-stack-transition stack nil))
      ((and keyword
            (string= keyword "case"))
       (%make-control-flow-stack-transition stack keyword))
      ((and keyword (%block-opening-keyword-p keyword))
       (%make-control-flow-stack-transition
        (%push-control-flow-frame stack keyword)
        nil))
      ((and keyword (string= keyword "else"))
       (if (%if-frame-accepts-else-p (first stack))
           (%make-control-flow-stack-transition
            (if (%else-if-header-p cmd)
                stack
                (%control-flow-stack-with-else-seen stack))
            nil)
           (%make-control-flow-stack-transition stack keyword)))
      ((and keyword (string= keyword "end"))
       (if stack
           (%make-control-flow-stack-transition (rest stack) nil)
           (%make-control-flow-stack-transition stack keyword)))
      (t
       (%make-control-flow-stack-transition stack nil)))))

(defun %unclosed-control-flow-p (cmds)
  (loop with stack = nil
        for cmd in cmds
        do (let ((transition (%control-flow-stack-transition stack cmd)))
             (setf stack
                   (%control-flow-stack-transition-stack transition)))
        finally (return (not (null stack)))))

(defstruct (%control-flow-diagnostic-span
            (:constructor %make-control-flow-diagnostic-span (start end)))
  (start 0 :type integer :read-only t)
  (end 0 :type integer :read-only t))

(defstruct (%control-flow-node-span
            (:constructor %make-control-flow-node-span (start end)))
  (start 0 :type integer :read-only t)
  (end 0 :type integer :read-only t))

(defun %control-flow-node-span-from-raw-span (span)
  (when (and (consp span) (consp (rest span)))
    (%make-control-flow-node-span (first span) (second span))))

(defun %control-flow-diagnostic-span-from-node-span (span input-length)
  (if span
      (%make-control-flow-diagnostic-span
       (%control-flow-node-span-start span)
       (%control-flow-node-span-end span))
      (%make-control-flow-diagnostic-span input-length input-length)))

(defun %control-flow-diagnostic-span-from-node (node input-length)
  (%control-flow-diagnostic-span-from-node-span
   (%control-flow-node-span-from-raw-span
    (and (ast-node-p node) (ast-node-span node)))
   input-length))

(defun %push-control-flow-diagnostic (diagnostics node keyword input-length)
  (let ((span (%control-flow-diagnostic-span-from-node node input-length)))
    (push (%make-parse-diagnostic
           :unexpected-control-flow
           (format nil "Unexpected '~a'" keyword)
           (%control-flow-diagnostic-span-start span)
           (%control-flow-diagnostic-span-end span))
          diagnostics)))

(defun %unexpected-control-flow-diagnostics (cmds input-length)
  (let ((stack nil)
        (diagnostics nil))
    (dolist (cmd cmds)
      (let* ((transition (%control-flow-stack-transition stack cmd))
             (unexpected-keyword
               (%control-flow-stack-transition-unexpected-keyword transition)))
        (setf stack
              (%control-flow-stack-transition-stack transition))
        (when unexpected-keyword
          (setf diagnostics
                (%push-control-flow-diagnostic
                 diagnostics cmd unexpected-keyword input-length)))))
    (nreverse diagnostics)))
