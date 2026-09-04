(in-package #:nshell.presentation)

(defun %history-last-argument-state (state argument start end index)
  (copy-input-state-clearing-completion
   state
   :buffer (concatenate 'string
                        (subseq (input-state-buffer state) 0 start)
                        argument
                        (subseq (input-state-buffer state) end))
   :cursor-pos (+ start (length argument))
   :last-argument-start start
   :last-argument-end (+ start (length argument))
   :last-argument-index index))

(defun %history-last-argument-selected-p (state)
  (let* ((buffer (input-state-buffer state))
         (start (input-state-last-argument-start state))
         (end (input-state-last-argument-end state))
         (index (input-state-last-argument-index state)))
    (and (integerp start)
         (integerp end)
         (integerp index)
         (<= 0 start end (length buffer))
         (let ((argument (nshell.domain.history:history-last-argument-at
                          *history* index)))
           (and argument
                (string= argument (subseq buffer start end)))))))

(defun %insert-history-last-argument-selected (state)
  (let* ((start (input-state-last-argument-start state))
         (end (input-state-last-argument-end state))
         (index (input-state-last-argument-index state))
         (argument (nshell.domain.history:history-last-argument-at
                    *history* (1+ index))))
    (if argument
        (let ((new-state (%history-last-argument-state
                          state argument start end (1+ index))))
          (%record-history-last-argument-transition
           state new-state :suggest-update)
          :suggest-update)
        :none)))

(defun %insert-history-last-argument-initial (state)
  (let ((argument (nshell.domain.history:history-last-argument-at *history* 0)))
    (if argument
        (let ((cursor (input-state-cursor-pos state)))
          (multiple-value-bind (inserted-state inserted-output)
              (insert-string-at-cursor state argument)
            (let ((new-state (%history-last-argument-state
                              inserted-state argument
                              cursor
                              (input-state-cursor-pos inserted-state)
                              0)))
              (%record-history-last-argument-transition
               state new-state inserted-output)
              inserted-output)))
        :none)))

(defun %record-history-last-argument-transition (old-state new-state output)
  (setf *input-state*
        (record-undo-transition
         old-state new-state output
         (nshell.infrastructure.terminal:make-key-event :alt-dot)))
  output)

(defun insert-history-last-argument ()
  (let ((old-state *input-state*))
    (if (%history-last-argument-selected-p old-state)
        (%insert-history-last-argument-selected old-state)
        (%insert-history-last-argument-initial old-state))))
