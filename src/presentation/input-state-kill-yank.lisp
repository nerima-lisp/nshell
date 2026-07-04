;;; Kill operations for the pure REPL input reducer.

(in-package #:nshell.presentation)

(defstruct (kill-edit-plan
            (:constructor %make-kill-edit-plan (start end cursor-pos))
            (:conc-name %kill-edit-plan-))
  (start 0 :type fixnum :read-only t)
  (end 0 :type fixnum :read-only t)
  (cursor-pos 0 :type fixnum :read-only t))

(defstruct (kill-edit
            (:constructor %make-kill-edit (plan))
            (:conc-name %kill-edit-))
  (plan (error "PLAN is required.") :type kill-edit-plan :read-only t))

(defun kill-edit-plan (edit)
  (%kill-edit-plan edit))

(defun kill-edit-plan-start (plan)
  (%kill-edit-plan-start plan))

(defun kill-edit-plan-end (plan)
  (%kill-edit-plan-end plan))

(defun kill-edit-plan-cursor-pos (plan)
  (%kill-edit-plan-cursor-pos plan))

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
    (let ((cursor (input-state-cursor-pos state)))
      (let ((start (previous-kill-word-start (input-state-buffer state) cursor)))
        (%kill-range state start cursor start)))))

(defun forward-kill-word (state)
  (with-normalized-cleared-completion-state (state state)
    (let ((cursor (input-state-cursor-pos state)))
      (%kill-range state
                   cursor
                   (next-kill-word-end (input-state-buffer state) cursor)
                   cursor))))

(defstruct (yank-edit-plan
            (:constructor %make-yank-edit-plan (start text buffer cursor-pos))
            (:conc-name %yank-edit-plan-))
  (start 0 :type fixnum :read-only t)
  (text "" :type string :read-only t)
  (buffer "" :type string :read-only t)
  (cursor-pos 0 :type fixnum :read-only t))

(defstruct (yank-edit
            (:constructor %make-yank-edit (plan))
            (:conc-name %yank-edit-))
  (plan (error "PLAN is required.") :type yank-edit-plan :read-only t))

(defun yank-edit-plan (edit)
  (%yank-edit-plan edit))

(defun yank-edit-plan-start (plan)
  (%yank-edit-plan-start plan))

(defun yank-edit-plan-text (plan)
  (%yank-edit-plan-text plan))

(defun yank-edit-plan-buffer (plan)
  (%yank-edit-plan-buffer plan))

(defun yank-edit-plan-cursor-pos (plan)
  (%yank-edit-plan-cursor-pos plan))

(defun yank-edit-for-state (state)
  (let ((killed (first (input-state-kill-ring state))))
    (when killed
      (let* ((buffer (input-state-buffer state))
             (cursor (input-state-cursor-pos state))
             (insertion (buffer-insertion-at-cursor buffer cursor killed)))
        (when insertion
          (%make-yank-edit
           (%make-yank-edit-plan
            cursor
            killed
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

(defstruct (yank-pop-edit-plan
            (:constructor %make-yank-pop-edit-plan
                (start end next-index replacement))
            (:conc-name %yank-pop-edit-plan-))
  (start 0 :type fixnum :read-only t)
  (end 0 :type fixnum :read-only t)
  (next-index 0 :type fixnum :read-only t)
  (replacement "" :type string :read-only t))

(defstruct (yank-pop-edit
            (:constructor %make-yank-pop-edit (plan))
            (:conc-name %yank-pop-edit-))
  (plan (error "PLAN is required.") :type yank-pop-edit-plan :read-only t))

(defun yank-pop-edit-plan (edit)
  (%yank-pop-edit-plan edit))

(defun yank-pop-edit-plan-start (plan)
  (%yank-pop-edit-plan-start plan))

(defun yank-pop-edit-plan-end (plan)
  (%yank-pop-edit-plan-end plan))

(defun yank-pop-edit-plan-next-index (plan)
  (%yank-pop-edit-plan-next-index plan))

(defun yank-pop-edit-plan-replacement (plan)
  (%yank-pop-edit-plan-replacement plan))

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
    (when (and ring
               start
               end
               index
               (<= 0 start)
               (< start end)
               (<= end (length buffer))
               (= end (input-state-cursor-pos state))
               (< index (length ring))
               (string= (subseq buffer start end)
                        (nth index ring)))
      (let ((next-index (mod (1+ index) (length ring))))
        (%make-yank-pop-edit
         (%make-yank-pop-edit-plan start
                                   end
                                   next-index
                                   (nth next-index ring)))))))

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
