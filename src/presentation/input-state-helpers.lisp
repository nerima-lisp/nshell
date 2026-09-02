; Input state mutation macros and high-level utility functions.

(in-package #:nshell.presentation)

(defmacro with-normalized-input-state ((state-var state-form) &body body)
  `(let ((,state-var (normalize-input-state ,state-form)))
     ,@body))

(defmacro with-input-buffer ((state-var buffer-var cursor-var) state-form &body body)
  `(let* ((,state-var (normalize-input-state ,state-form))
          (,buffer-var (input-state-buffer ,state-var))
          (,cursor-var (input-state-cursor-pos ,state-var)))
     ,@body))

(defmacro with-buffer-edit ((state-var buffer-var cursor-var) state-form &body body)
  `(with-input-buffer (,state-var ,buffer-var ,cursor-var) ,state-form
     (flet ((commit-buffer-edit (new-buffer &key cursor-pos)
              (values (copy-input-state-clearing-completion ,state-var
                       :buffer new-buffer
                       :cursor-pos (or cursor-pos
                                       (input-state-cursor-pos ,state-var)))
                      :suggest-update)))
       ,@body)))

(defmacro with-normalized-cleared-completion-state ((state-var state-form) &body body)
  `(let ((,state-var (clear-completion-session-state
                      (normalize-input-state ,state-form))))
     ,@body))

(defun input-state-at-eol-p (state)
  (let ((state (normalize-input-state state)))
    (= (input-state-cursor-pos state)
       (length (input-state-buffer state)))))

(define-value-struct %input-session-clear
    ((kind nil :type symbol)
     (overrides nil :type list :copy :list))
  :constructor %make-input-session-clear
  :public-accessors nil)

(defun %completion-session-clear-overrides ()
  (list :completion-index -1
        :completion-base-buffer :clear
        :completion-base-cursor :clear
        :last-candidates :clear
        :suggestion :clear))

(defun %history-search-session-clear-overrides ()
  (list :search-query :clear
        :search-original-buffer :clear
        :search-original-cursor :clear
        :search-index 0))

(defun %assert-input-session-clear-kind (clear kind)
  (unless (and (%input-session-clear-p clear)
               (eq kind (%input-session-clear-kind clear)))
    (error "Expected input session clear kind ~S, got ~S"
           kind
           clear))
  clear)

(defun completion-session-clear ()
  (%make-input-session-clear :completion
                             (%completion-session-clear-overrides)))

(defun history-search-session-clear ()
  (%make-input-session-clear :history-search
                             (%history-search-session-clear-overrides)))

(defun apply-input-session-clear (state clear)
  (check-type clear %input-session-clear)
  (apply #'copy-input-state-with
         state
         (%input-session-clear-overrides clear)))

(defun apply-completion-session-clear (state clear)
  (apply-input-session-clear
   state
   (%assert-input-session-clear-kind clear :completion)))

(defun apply-history-search-session-clear (state clear)
  (apply-input-session-clear
   state
   (%assert-input-session-clear-kind clear :history-search)))

(defun clear-completion-session-state (state)
  (apply-completion-session-clear state (completion-session-clear)))

(defun clear-history-search-session-state (state)
  (apply-history-search-session-clear state (history-search-session-clear)))

(defun copy-input-state-clearing-completion (state &rest args)
  (apply #'copy-input-state-with
         (clear-completion-session-state state)
         args))

(defun expand-abbreviation-before-cursor (state)
  "Expand the token immediately before cursor if STATE has an expander."
  (with-buffer-edit (state buffer cursor) state
    (let ((expander (input-state-abbreviation-expander state)))
      (multiple-value-bind (new-buffer new-cursor expanded-p)
          (nshell.domain.abbreviation:expand-abbreviation
           buffer cursor expander :max-length +max-input-buffer-size+)
        (if (not expanded-p)
            (values state nil)
            (commit-buffer-edit new-buffer :cursor-pos new-cursor))))))

(defun finalize-enter-input-state (state)
  (with-normalized-input-state (state state)
    (let ((suggestion (and (input-state-at-eol-p state)
                           (input-state-suggestion state)))
          (state (expand-abbreviation-before-cursor state)))
      (when suggestion
        (setf state (append-suggestion-to-input-state state suggestion)))
      (values state :execute))))

(defun insert-char-with-abbreviation-expansion (state ch)
  (if (nshell.domain.abbreviation:abbreviation-boundary-p ch)
      (multiple-value-bind (expanded-state expanded-p)
          (expand-abbreviation-before-cursor state)
        (declare (ignore expanded-p))
        (insert-char-at-cursor expanded-state ch))
      (insert-char-at-cursor state ch)))
