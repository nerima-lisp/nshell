;;; Kill operations for the pure REPL input reducer.

(in-package #:nshell.presentation)

(defstruct (kill-edit
            (:constructor %make-kill-edit (start end cursor-pos))
            (:conc-name %kill-edit-))
  (start 0 :type fixnum :read-only t)
  (end 0 :type fixnum :read-only t)
  (cursor-pos 0 :type fixnum :read-only t))

(defun kill-edit-start (edit)
  (%kill-edit-start edit))

(defun kill-edit-end (edit)
  (%kill-edit-end edit))

(defun kill-edit-cursor-pos (edit)
  (%kill-edit-cursor-pos edit))

(defun kill-edit-empty-p (edit)
  (= (kill-edit-start edit)
     (kill-edit-end edit)))

(defun kill-edit-killed-text (edit buffer)
  (subseq buffer (kill-edit-start edit) (kill-edit-end edit)))

(defun kill-edit-buffer (edit buffer)
  (concatenate 'string
               (subseq buffer 0 (kill-edit-start edit))
               (subseq buffer (kill-edit-end edit))))

(defun commit-kill-edit (state edit)
  (if (kill-edit-empty-p edit)
      (values state :none)
      (let* ((buffer (input-state-buffer state))
             (killed (kill-edit-killed-text edit buffer)))
        (values (copy-input-state-clearing-completion
                 state
                 :buffer (kill-edit-buffer edit buffer)
                 :cursor-pos (kill-edit-cursor-pos edit)
                 :kill-ring (cons killed (input-state-kill-ring state)))
                :suggest-update))))

(defun %kill-range (state start end cursor-pos)
  (commit-kill-edit state (%make-kill-edit start end cursor-pos)))

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

(defun yank-last-kill (state)
  (with-normalized-cleared-completion-state (state state)
    (let ((killed (first (input-state-kill-ring state))))
      (if killed
          (let ((start (input-state-cursor-pos state)))
            (multiple-value-bind (new-state output)
                (insert-string-at-cursor state killed)
              (values (copy-input-state-clearing-completion
                       new-state
                       :last-yank-start start
                       :last-yank-end (input-state-cursor-pos new-state)
                       :last-yank-index 0)
                      output)))
          (values state :none)))))

(defstruct (yank-pop-edit
            (:constructor %make-yank-pop-edit (start end next-index replacement))
            (:conc-name %yank-pop-edit-))
  (start 0 :type fixnum :read-only t)
  (end 0 :type fixnum :read-only t)
  (next-index 0 :type fixnum :read-only t)
  (replacement "" :type string :read-only t))

(defun yank-pop-edit-start (edit)
  (%yank-pop-edit-start edit))

(defun yank-pop-edit-end (edit)
  (%yank-pop-edit-end edit))

(defun yank-pop-edit-next-index (edit)
  (%yank-pop-edit-next-index edit))

(defun yank-pop-edit-replacement (edit)
  (%yank-pop-edit-replacement edit))

(defun yank-pop-edit-cursor-pos (edit)
  (+ (yank-pop-edit-start edit)
     (length (yank-pop-edit-replacement edit))))

(defun yank-pop-edit-buffer (edit buffer)
  (concatenate 'string
               (subseq buffer 0 (yank-pop-edit-start edit))
               (yank-pop-edit-replacement edit)
               (subseq buffer (yank-pop-edit-end edit))))

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
        (%make-yank-pop-edit start end next-index (nth next-index ring))))))

(defun commit-yank-pop-edit (state edit)
  (let ((new-end (yank-pop-edit-cursor-pos edit)))
    (values (copy-input-state-clearing-completion
             state
             :buffer (yank-pop-edit-buffer edit (input-state-buffer state))
             :cursor-pos new-end
             :last-yank-start (yank-pop-edit-start edit)
             :last-yank-end new-end
             :last-yank-index (yank-pop-edit-next-index edit))
            :suggest-update)))

(defun cycle-last-yank (state)
  (with-normalized-cleared-completion-state (state state)
    (let ((edit (yank-pop-edit-for-state state)))
      (if edit
          (commit-yank-pop-edit state edit)
          (values state :none)))))