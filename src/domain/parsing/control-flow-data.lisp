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
            (:constructor %make-control-flow-frame (keyword)))
  (keyword nil :type string)
  (else-seen nil :type boolean))

(defun control-flow-keyword-p (value)
  (and (stringp value)
       (not (null (member value +control-flow-keywords+ :test #'string=)))))

(defun %command-keyword (node)
  (when (command-node-p node)
    (let ((command (command-node-command node)))
      (and (control-flow-keyword-p command) command))))

(defun %block-opening-keyword-p (keyword)
  (not (null (member keyword +control-flow-block-keywords+ :test #'string=))))

(defun %command-first-arg-value (header &optional (default ""))
  (let ((args (and (command-node-p header) (command-node-args header))))
    (if args
        (arg-value (first args))
        default)))

(defun %command-from-header-args (header)
  (let ((args (command-node-args header)))
    (when args
      (make-command-node (arg-value (first args))
                         (rest args)
                         nil
                         (arg-quote-style (first args))))))

(defun %else-if-header-p (header)
  (and (command-node-p header)
       (let ((args (command-node-args header)))
         (and args
              (string= "if" (arg-value (first args)))))))

(defun %consume-control-flow-terminator (nodes keyword)
  (if (and nodes (string= (%command-keyword (first nodes)) keyword))
      (rest nodes)
      nodes))

(defun %stack-top-keyword (stack)
  (let ((top (first stack)))
    (cond
      ((stringp top) top)
      ((control-flow-frame-p top) (control-flow-frame-keyword top))
      (t nil))))

(defun %case-within-switch-p (keyword stack)
  (and keyword
       (string= keyword "case")
       (string= (%stack-top-keyword stack) "switch")))

(defun %unclosed-control-flow-p (cmds)
  (loop with stack = nil
        for cmd in cmds
        for keyword = (%command-keyword cmd)
        do (cond
             ((and keyword
                   (string= keyword "case")
                   (%case-within-switch-p keyword stack)))
             ((and keyword
                   (string= keyword "case"))
              nil)
             ((and keyword (%block-opening-keyword-p keyword))
              (push keyword stack))
             ((and keyword (string= keyword "end") stack)
              (pop stack)))
        finally (return (not (null stack)))))

(defun %command-diagnostic-span (node input-length)
  (let ((span (and (ast-node-p node) (ast-node-span node))))
    (if (and (consp span) (consp (rest span)))
        (values (first span) (second span))
        (values input-length input-length))))

(defun %push-control-flow-diagnostic (diagnostics node keyword input-length)
  (multiple-value-bind (start end)
      (%command-diagnostic-span node input-length)
    (push (make-parse-diagnostic
           :unexpected-control-flow
           (format nil "Unexpected '~a'" keyword)
           start
           end)
          diagnostics)))

(defun %push-control-flow-frame (stack keyword)
  (push (%make-control-flow-frame keyword) stack))

(defun %unexpected-control-flow-diagnostics (cmds input-length)
  (let ((stack nil)
        (diagnostics nil))
    (dolist (cmd cmds)
      (let ((keyword (%command-keyword cmd)))
        (cond
          ((and keyword
                (string= keyword "case")
                (%case-within-switch-p keyword stack)))
          ((and keyword
                (string= keyword "case"))
           (setf diagnostics
                 (%push-control-flow-diagnostic diagnostics cmd keyword input-length)))
          ((and keyword (%block-opening-keyword-p keyword))
           (setf stack (%push-control-flow-frame stack keyword)))
          ((and keyword (string= keyword "else"))
           (if (and stack
                    (string= (control-flow-frame-keyword (first stack)) "if")
                    (not (control-flow-frame-else-seen (first stack))))
               (unless (%else-if-header-p cmd)
                 (setf (control-flow-frame-else-seen (first stack)) t))
               (setf diagnostics
                     (%push-control-flow-diagnostic diagnostics cmd keyword input-length))))
          ((and keyword (string= keyword "end"))
           (if stack
               (pop stack)
               (setf diagnostics
                     (%push-control-flow-diagnostic diagnostics cmd keyword input-length)))))))
    (nreverse diagnostics)))
