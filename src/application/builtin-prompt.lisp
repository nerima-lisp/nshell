(in-package #:nshell.application)

(defvar *prompt-format-apply-handler* nil
  "NIL, or a function of two arguments SIDE VALUE (SIDE is :LEFT or :RIGHT,
VALUE a format string or NIL to restore that side's default) that the
interactive session installs so the prompt builtin can update the live
session's prompt format.")

(defvar *prompt-format-query-handler* nil
  "NIL, or a function of no arguments returning two values, the currently
active left and right prompt format text, that the interactive session
installs so the prompt builtin can read live state.")

(defvar *prompt-preview-handler* nil
  "NIL, or a function of one FORMAT argument returning the text PROMPT
PREVIEW prints: FORMAT rendered once against the live session state as a
left prompt, without installing it.")

(defun %builtin-prompt-usage ()
  (%builtin-usage "prompt" "prompt [show|left FORMAT|right FORMAT|reset|preview FORMAT]"))

(defun %prompt-invalid-format-output (condition)
  (values (format nil "prompt: unknown segment {~a}~%"
                  (nshell.domain.prompting:invalid-prompt-format-segment condition))
          2))

(defun %prompt-show-output ()
  (multiple-value-bind (left right)
      (if (functionp *prompt-format-query-handler*)
          (funcall *prompt-format-query-handler*)
          (values nshell.domain.prompting:+default-left-prompt-format+
                  nshell.domain.prompting:+default-right-prompt-format+))
    (format nil "left:  ~a~%right: ~a~%" left right)))

(defun %prompt-set (side value)
  (handler-case
      (progn
        (nshell.domain.prompting:parse-prompt-format value)
        (when (functionp *prompt-format-apply-handler*)
          (funcall *prompt-format-apply-handler* side value))
        (values nil 0))
    (nshell.domain.prompting:invalid-prompt-format (condition)
      (%prompt-invalid-format-output condition))))

(defun %prompt-reset ()
  (when (functionp *prompt-format-apply-handler*)
    (funcall *prompt-format-apply-handler* :left nil)
    (funcall *prompt-format-apply-handler* :right nil))
  (values nil 0))

(defun %prompt-preview (format)
  (handler-case
      (progn
        (nshell.domain.prompting:parse-prompt-format format)
        (values (format nil "~a~%"
                        (if (functionp *prompt-preview-handler*)
                            (funcall *prompt-preview-handler* format)
                            ""))
                0))
    (nshell.domain.prompting:invalid-prompt-format (condition)
      (%prompt-invalid-format-output condition))))

(define-builtin %builtin-prompt (context args) (context)
  (cond
    ((or (null args) (and (string-equal (first args) "show") (null (rest args))))
     (values (%prompt-show-output) 0))
    ((and (string-equal (first args) "left") (rest args))
     (%prompt-set :left (%string-join (rest args) " ")))
    ((and (string-equal (first args) "right") (rest args))
     (%prompt-set :right (%string-join (rest args) " ")))
    ((and (string-equal (first args) "reset") (null (rest args)))
     (%prompt-reset))
    ((and (string-equal (first args) "preview") (rest args))
     (%prompt-preview (%string-join (rest args) " ")))
    (t (%builtin-prompt-usage))))
