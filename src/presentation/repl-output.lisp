;;; REPL output-event dispatcher
(in-package #:nshell.presentation)

(defun process-output-event (output-event)
  (case output-event
    (:execute (%process-execute-output-event))
    (:quit (%process-quit-output-event))
    (:complete (%process-complete-output-event))
    (:suggest-update (%process-suggest-update-output-event))
    ((:search-start :search-update) (%process-history-search-output-event))
    (:history-prev (%process-history-prev-output-event))
    (:history-next (%process-history-next-output-event))
    (:clear-screen (%process-clear-screen-output-event))
    (:insert-last-argument (%process-insert-last-argument-output-event))
    (:copy (%process-copy-output-event))
    (:redraw (%process-redraw-output-event))
    (t (%process-default-output-event))))
