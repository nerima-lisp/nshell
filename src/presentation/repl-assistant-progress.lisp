;;; Assistant waiting-state presentation
(in-package #:nshell.presentation)

;; The measured structured-output median is about 31 seconds. Five seconds is
;; too early to ask users to abandon a request that is still within its normal
;; waiting window, so the choice appears at roughly half that observed median.
(defconstant +assistant-progress-choice-threshold-ms+ 15000)

(defun %assistant-progress-elapsed-ms (started-at current-time)
  (max 0
       (round (* 1000
                 (/ (- current-time started-at)
                    internal-time-units-per-second)))))

(defun assistant-progress-lines (started-at &key current-time)
  (let* ((now (if (null current-time)
                  (boundary-monotonic)
                  current-time))
         (elapsed-ms (%assistant-progress-elapsed-ms started-at now))
         (elapsed-seconds (floor elapsed-ms 1000)))
    (list
     (if (>= elapsed-ms +assistant-progress-choice-threshold-ms+)
         (format nil
                 "thinking… ~Ds · ⌃C cancel · まだ待つ / 諦める"
                 elapsed-seconds)
         (format nil "thinking… ~Ds · ⌃C cancel" elapsed-seconds)))))

(defun render-assistant-progress-panel
    (started-at &key current-time (terminal-width (terminal-width)))
  (render-transient-panel
   (assistant-progress-lines started-at :current-time current-time)
   :terminal-width terminal-width))
