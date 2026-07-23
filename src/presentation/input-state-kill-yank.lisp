;;; Kill operations for the pure REPL input reducer.

(in-package #:nshell.presentation)

(define-value-struct %kill-edit-plan
    ((start 0 :type fixnum)
     (end 0 :type fixnum)
     (cursor-pos 0 :type fixnum)))

(define-value-struct %kill-edit
    ((plan (error "PLAN is required.") :type %kill-edit-plan)))

(defun kill-edit-empty-p (edit)
  (let ((plan (kill-edit-plan edit)))
    (= (kill-edit-plan-start plan)
       (kill-edit-plan-end plan))))

(defun kill-edit-killed-text (edit buffer)
  (let ((plan (kill-edit-plan edit)))
    (subseq buffer
            (kill-edit-plan-start plan)
            (kill-edit-plan-end plan))))

(defun kill-edit-buffer (edit buffer)
  (let ((plan (kill-edit-plan edit)))
    (concatenate 'string
                 (subseq buffer 0 (kill-edit-plan-start plan))
                 (subseq buffer (kill-edit-plan-end plan)))))

(defun commit-kill-edit (state edit)
  (if (kill-edit-empty-p edit)
      (values state :none)
      (let* ((plan (kill-edit-plan edit))
             (buffer (input-state-buffer state))
             (killed (kill-edit-killed-text edit buffer)))
        (values (copy-input-state-clearing-completion
                 state
                 :buffer (kill-edit-buffer edit buffer)
                 :cursor-pos (kill-edit-plan-cursor-pos plan)
                 :kill-ring (cons killed (input-state-kill-ring state)))
                :suggest-update))))

(defun %kill-range (state start end cursor-pos)
  (commit-kill-edit state
                    (%make-kill-edit
                     (%make-kill-edit-plan start end cursor-pos))))

(defun backward-kill-word (state)
  (with-normalized-cleared-completion-state (state state)
    (let* ((cursor (input-state-cursor-pos state))
           (start (previous-kill-word-start (input-state-buffer state) cursor)))
      (%kill-range state
                   start
                   cursor
                   start))))

(defun forward-kill-word (state)
  (with-normalized-cleared-completion-state (state state)
    (let ((cursor (input-state-cursor-pos state)))
      (%kill-range state
                   cursor
                   (next-kill-word-end (input-state-buffer state) cursor)
                   cursor))))

(define-value-struct %kill-ring-selection
    ((index 0 :type fixnum)
     (text "" :type string)))

(defun kill-ring-first-selection (state)
  (let ((ring (input-state-kill-ring state)))
    (when ring
      (%make-kill-ring-selection 0 (first ring)))))

(defun kill-ring-selection-at (ring index)
  (when (and ring index (<= 0 index) (< index (length ring)))
    (%make-kill-ring-selection index (nth index ring))))

(defun kill-ring-next-selection (ring selection)
  (let ((next-index (mod (1+ (kill-ring-selection-index selection))
                         (length ring))))
    (%make-kill-ring-selection next-index (nth next-index ring))))

(define-value-struct %yank-edit-plan
    ((start 0 :type fixnum)
     (text "" :type string)
     (buffer "" :type string)
     (cursor-pos 0 :type fixnum)))

(define-value-struct %yank-edit
    ((plan (error "PLAN is required.") :type %yank-edit-plan)))

(defun yank-edit-for-state (state)
  (let ((selection (kill-ring-first-selection state)))
    (when selection
      (let* ((buffer (input-state-buffer state))
             (cursor (input-state-cursor-pos state))
             (text (kill-ring-selection-text selection))
             (insertion (buffer-insertion-at-cursor buffer cursor text)))
        (when insertion
          (%make-yank-edit
           (%make-yank-edit-plan
            cursor
            text
            (buffer-insertion-result insertion buffer)
            (buffer-insertion-cursor-pos insertion))))))))

(defun commit-yank-edit (state edit)
  (let ((plan (yank-edit-plan edit)))
    (values (copy-input-state-clearing-completion
             state
             :buffer (yank-edit-plan-buffer plan)
             :cursor-pos (yank-edit-plan-cursor-pos plan)
             :last-yank-start (yank-edit-plan-start plan)
             :last-yank-end (yank-edit-plan-cursor-pos plan)
             :last-yank-index 0)
            :suggest-update)))

(defun yank-last-kill (state)
  (with-normalized-cleared-completion-state (state state)
    (let ((edit (yank-edit-for-state state)))
      (if edit
          (commit-yank-edit state edit)
          (values state :none)))))

(define-value-struct %yank-pop-edit-plan
    ((start 0 :type fixnum)
     (end 0 :type fixnum)
     (next-index 0 :type fixnum)
     (replacement "" :type string)))

(define-value-struct %yank-pop-edit
    ((plan (error "PLAN is required.") :type %yank-pop-edit-plan)))

(defun yank-pop-edit-plan-cursor-pos (plan)
  (+ (yank-pop-edit-plan-start plan)
     (length (yank-pop-edit-plan-replacement plan))))

(defun yank-pop-edit-plan-buffer (plan buffer)
  (concatenate 'string
               (subseq buffer 0 (yank-pop-edit-plan-start plan))
               (yank-pop-edit-plan-replacement plan)
               (subseq buffer (yank-pop-edit-plan-end plan))))

(defun yank-pop-edit-for-state (state)
  (let* ((ring (input-state-kill-ring state))
         (buffer (input-state-buffer state))
         (start (input-state-last-yank-start state))
         (end (input-state-last-yank-end state))
         (index (input-state-last-yank-index state)))
    (let ((selection (kill-ring-selection-at ring index)))
      (when (and selection
                 start
                 end
                 (<= 0 start)
                 (< start end)
                 (<= end (length buffer))
                 (= end (input-state-cursor-pos state))
                 (string= (subseq buffer start end)
                          (kill-ring-selection-text selection)))
        (let ((next-selection (kill-ring-next-selection ring selection)))
          (%make-yank-pop-edit
           (%make-yank-pop-edit-plan start
                                     end
                                     (kill-ring-selection-index next-selection)
                                     (kill-ring-selection-text next-selection))))))))

(defun commit-yank-pop-edit (state edit)
  (let* ((plan (yank-pop-edit-plan edit))
         (new-end (yank-pop-edit-plan-cursor-pos plan)))
    (values (copy-input-state-clearing-completion
             state
             :buffer (yank-pop-edit-plan-buffer
                      plan
                      (input-state-buffer state))
             :cursor-pos new-end
             :last-yank-start (yank-pop-edit-plan-start plan)
             :last-yank-end new-end
             :last-yank-index (yank-pop-edit-plan-next-index plan))
            :suggest-update)))

(defun cycle-last-yank (state)
  (with-normalized-cleared-completion-state (state state)
    (let ((edit (yank-pop-edit-for-state state)))
      (if edit
          (commit-yank-pop-edit state edit)
          (values state :none)))))
