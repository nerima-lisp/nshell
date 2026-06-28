(in-package #:nshell.domain.parsing)

(defun %pipeline-or-command-node (commands)
  (if (= (length commands) 1)
      (first commands)
      (make-pipeline-node commands)))

(defun %pipeline-separators-p (separators)
  (every (lambda (separator)
           (eq separator :pipe))
         (butlast separators)))

(defun %sequence-separators-p (separators)
  (every (lambda (separator)
           (not (eq separator :pipe)))
         (butlast separators)))

(defun %flush-mixed-sequence-pipe-group (sequence-commands pipe-group)
  (if pipe-group
      (values (cons (%pipeline-or-command-node (nreverse pipe-group))
                    sequence-commands)
              nil)
      (values sequence-commands pipe-group)))

(defun %build-mixed-sequence (commands separators)
  (let ((sequence-commands nil)
        (sequence-separators nil)
        (pipe-group nil))
    (loop for command in commands
          for index from 0
          for separator = (nth index separators)
          do (push command pipe-group)
             (when (and separator (not (eq separator :pipe)))
               (multiple-value-setq (sequence-commands pipe-group)
                 (%flush-mixed-sequence-pipe-group sequence-commands pipe-group))
               (push separator sequence-separators)))
    (multiple-value-setq (sequence-commands pipe-group)
      (%flush-mixed-sequence-pipe-group sequence-commands pipe-group))
    (make-sequence-node (nreverse sequence-commands)
                        (nreverse sequence-separators))))

(defun %build-ast-from-command-list (command-list)
  (let* ((commands (mapcar #'first command-list))
         (separators (mapcar #'second command-list))
         (last-separator (car (last separators))))
    (cond
      ((null commands) nil)
      ((= (length commands) 1)
       (if (eq :amp (first separators))
           (make-sequence-node commands '(:amp))
           (first commands)))
      ((%pipeline-separators-p separators)
       (let ((node (make-pipeline-node commands)))
         (if (eq :amp last-separator)
             (make-sequence-node (list node) '(:amp))
             node)))
      ((%sequence-separators-p separators)
       (make-sequence-node commands
                           (if (eq :amp last-separator)
                               separators
                               (butlast separators))))
      (t
       (%build-mixed-sequence commands separators)))))
