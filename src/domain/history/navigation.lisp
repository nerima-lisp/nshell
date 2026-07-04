(in-package #:nshell.domain.history)

(defun %history-prefix-match-p (prefix text)
  "Return true when TEXT matches PREFIX for history navigation."
  (history-match-line-prefix (make-history-entry text) prefix
                             :case-sensitive (some #'upper-case-p prefix)))

(defun %history-navigation-current-prefix (history current-prefix)
  (or (command-history-navigate-prefix history)
      current-prefix))

(defun %history-navigation-remember-origin (history current-prefix)
  (setf (command-history-navigate-prefix history) current-prefix
        (command-history-navigate-origin history) current-prefix)
  history)

(defun %history-navigation-update-index (history index)
  (setf (command-history-navigate-index history) index)
  history)

(defun %history-navigation-reset-to-origin (history)
  (let ((origin (command-history-navigate-origin history)))
    (%history-clear-navigation history)
    origin))

(defun %history-navigation-find-previous-match (entries start prefix)
  (loop for entry in (nthcdr start entries)
        for i from start
        for text = (entry-text entry)
        when (%history-prefix-match-p prefix text)
          do (return (values i text))))

(defun %history-navigation-find-next-match (history idx prefix)
  (let ((matched-index nil)
        (matched-text nil))
    (loop for entry in (command-history-entries history)
          for i from 0 below idx
          for text = (entry-text entry)
          when (%history-prefix-match-p prefix text)
            do (setf matched-index i
                     matched-text text))
    (values matched-index matched-text)))

(defun history-previous (history current-prefix)
  "Navigate to the previous older history entry matching CURRENT-PREFIX."
  (let* ((entries (command-history-entries history))
         (idx (command-history-navigate-index history))
         (prefix (%history-navigation-current-prefix history current-prefix))
         (start (if (< idx 0) 0 (1+ idx))))
    (multiple-value-bind (matched-index matched-text)
        (%history-navigation-find-previous-match entries start prefix)
      (when matched-text
        (when (< idx 0)
          (%history-navigation-remember-origin history current-prefix))
        (%history-navigation-update-index history matched-index)
        matched-text))))

(defun history-next (history)
  "Navigate to the next newer history entry."
  (let ((idx (command-history-navigate-index history))
        (prefix (command-history-navigate-prefix history)))
    (if (> idx 0)
        (multiple-value-bind (matched-index matched-text)
            (%history-navigation-find-next-match history idx (or prefix ""))
          (if matched-text
              (progn
                (%history-navigation-update-index history matched-index)
                matched-text)
              (%history-navigation-reset-to-origin history)))
        (%history-navigation-reset-to-origin history))))

(defun history-reset-navigation (history)
  "Reset history navigation state after command execution."
  (%history-clear-navigation history))
