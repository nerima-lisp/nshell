(in-package #:nshell.domain.history)

(defun %history-cap-entries (history entries)
  (subseq entries 0 (min (length entries)
                         (command-history-max-entries history))))

(defun %history-unique-entries (entries)
  (let ((seen (make-hash-table :test #'equal)))
    (loop for entry in entries
          for text = (entry-text entry)
          unless (gethash text seen)
            do (setf (gethash text seen) t)
            and collect entry)))

(defun %history-replace-entries (history entries &key clear-navigation-p)
  (setf (command-history-entries history)
        (%history-cap-entries history entries))
  (when clear-navigation-p
    (%history-clear-navigation history))
  history)

(defun history-add (history text &optional exit-code)
  "Add TEXT to HISTORY and keep the newest entry for duplicate command text."
  (let* ((entry (make-history-entry text (get-universal-time) exit-code))
         (new-entries (%history-unique-entries
                       (cons entry (command-history-entries history)))))
    (%history-replace-entries history new-entries)))

(defun history-all (history)
  "Return all history entries, most recent first."
  (command-history-entries history))

(defun history-empty-p (history)
  "True if HISTORY has no entries."
  (null (command-history-entries history)))

(defun history-clear (history)
  "Remove all entries from HISTORY and reset transient navigation."
  (%history-replace-entries history nil :clear-navigation-p t))

(defun history-delete (history text &key (case-sensitive t))
  "Delete entries whose text exactly matches TEXT and return the deleted count."
  (let* ((old-entries (command-history-entries history))
         (new-entries
           (remove-if (lambda (entry)
                        (%history-text-equal-p (entry-text entry) text
                                               :case-sensitive case-sensitive))
                      old-entries))
         (deleted (- (length old-entries) (length new-entries))))
    (%history-replace-entries history new-entries)
    (when (plusp deleted)
      (%history-clear-navigation history))
    deleted))

(defun history-size (history)
  "Return current number of entries in HISTORY."
  (length (command-history-entries history)))

(defun history-merge (history entries)
  "Merge ENTRIES into HISTORY, preserving newest-first de-duplicated order."
  (let ((source-entries (if (command-history-p entries)
                            (command-history-entries entries)
                            entries)))
    (dolist (entry (reverse source-entries) history)
      (history-add history
                   (history-entry-text entry)
                   (history-entry-exit-code entry)))))
