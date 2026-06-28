(in-package #:nshell.domain.history)

(defun %history-prefix-match-p (prefix text)
  "Return true when TEXT matches PREFIX for history navigation."
  (history-match-line-prefix (make-history-entry text) prefix
                             :case-sensitive (some #'upper-case-p prefix)))

(defun history-previous (history current-prefix)
  "Navigate to the previous older history entry matching CURRENT-PREFIX."
  (let* ((entries (command-history-entries history))
         (idx (command-history-navigate-index history))
         (prefix (if (< idx 0)
                     current-prefix
                     (or (command-history-navigate-prefix history)
                         current-prefix)))
         (start (if (< idx 0) 0 (1+ idx))))
    (loop for entry in (nthcdr start entries)
          for i from start
          for text = (entry-text entry)
          when (%history-prefix-match-p prefix text)
            do (when (< idx 0)
                 (setf (command-history-navigate-prefix history) current-prefix
                       (command-history-navigate-origin history) current-prefix))
               (setf (command-history-navigate-index history) i)
               (return text)
          finally (return nil))))

(defun history-next (history)
  "Navigate to the next newer history entry."
  (let ((idx (command-history-navigate-index history))
        (prefix (command-history-navigate-prefix history)))
    (if (> idx 0)
        (let ((matched-index nil)
              (matched-text nil))
          (loop for entry in (command-history-entries history)
                for i from 0 below idx
                for text = (entry-text entry)
                when (%history-prefix-match-p (or prefix "") text)
                  do (setf matched-index i
                           matched-text text))
          (if matched-index
              (progn
                (setf (command-history-navigate-index history) matched-index)
                matched-text)
              (let ((origin (command-history-navigate-origin history)))
                (%history-clear-navigation history)
                origin)))
        (let ((origin (command-history-navigate-origin history)))
          (%history-clear-navigation history)
          origin))))

(defun history-reset-navigation (history)
  "Reset history navigation state after command execution."
  (%history-clear-navigation history))
