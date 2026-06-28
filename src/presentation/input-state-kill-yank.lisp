;;; Kill operations for the pure REPL input reducer.

(in-package #:nshell.presentation)

(defun %kill-range (state start end cursor-pos)
  (if (= start end)
      (values state :none)
      (let* ((buffer (input-state-buffer state))
             (killed (subseq buffer start end))
             (new-buffer (concatenate 'string
                                      (subseq buffer 0 start)
                                      (subseq buffer end))))
        (values (copy-input-state-clearing-completion
                 state
                 :buffer new-buffer
                 :cursor-pos cursor-pos
                 :kill-ring (cons killed (input-state-kill-ring state)))
                :suggest-update))))

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

(defun cycle-last-yank (state)
  (with-normalized-cleared-completion-state (state state)
    (let* ((ring (input-state-kill-ring state))
           (buffer (input-state-buffer state))
           (start (input-state-last-yank-start state))
           (end (input-state-last-yank-end state))
           (index (input-state-last-yank-index state)))
      (if (and ring
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
          (let* ((next-index (mod (1+ index) (length ring)))
                 (replacement (nth next-index ring))
                 (new-buffer (concatenate 'string
                                          (subseq buffer 0 start)
                                          replacement
                                          (subseq buffer end)))
                 (new-end (+ start (length replacement))))
            (values (copy-input-state-clearing-completion
                     state
                     :buffer new-buffer
                     :cursor-pos new-end
                     :last-yank-start start
                     :last-yank-end new-end
                     :last-yank-index next-index)
                    :suggest-update))
          (values state :none)))))
