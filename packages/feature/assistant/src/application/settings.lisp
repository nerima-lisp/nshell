(in-package #:nshell.feature.assistant)

(defstruct (assistant-usage
            (:constructor %make-assistant-usage (turns input-tokens
                                                output-tokens total-cost-usd
                                                last-rate-limit-status)))
  (turns 0)
  (input-tokens 0)
  (output-tokens 0)
  (total-cost-usd 0)
  last-rate-limit-status)

(defvar *assistant-usage* (%make-assistant-usage 0 0 0 0 nil))
(defvar *assistant-settings* (make-hash-table :test #'equal))

(defun reset-assistant-usage ()
  (setf *assistant-usage* (%make-assistant-usage 0 0 0 0 nil)))

(defun record-assistant-result-usage (payload)
  (let ((delta (assistant-result-usage payload)))
    (incf (assistant-usage-turns *assistant-usage*)
          (assistant-usage-delta-turns delta))
    (incf (assistant-usage-input-tokens *assistant-usage*)
          (assistant-usage-delta-input-tokens delta))
    (incf (assistant-usage-output-tokens *assistant-usage*)
          (assistant-usage-delta-output-tokens delta))
    (incf (assistant-usage-total-cost-usd *assistant-usage*)
          (assistant-usage-delta-total-cost-usd delta))
    *assistant-usage*))

(defun record-assistant-rate-limit (payload)
  (let ((status (assistant-rate-limit-status payload)))
    (when status
      (setf (assistant-usage-last-rate-limit-status *assistant-usage*) status))
    status))

(defun %assistant-setting-name (key)
  (let ((name (string-downcase (if (keywordp key)
                                  (symbol-name key)
                                  (princ-to-string key)))))
    (cond
      ((string= name "max_steps") "max-steps")
      ((string= name "budget_usd") "budget")
      (t name))))

(defun assistant-setting-environment-name (key)
  (cdr (assoc (%assistant-setting-name key)
              '(("effort" . "NSHELL_AI_EFFORT")
                ("model" . "NSHELL_AI_MODEL")
                ("max-steps" . "NSHELL_AI_MAX_STEPS")
                ("budget" . "NSHELL_AI_BUDGET_USD"))
              :test #'string=)))

(defun %assistant-setting-environment-value (key)
  (let ((name (assistant-setting-environment-name key)))
    (and name (uiop:getenv name))))

(defun %assistant-parse-positive-integer (value)
  (cond
    ((and (integerp value) (plusp value)) value)
    ((stringp value)
     (handler-case
         (let ((number (parse-integer value :junk-allowed nil)))
           (and (plusp number) number))
       (error () nil)))))

(defun %assistant-parse-budget (value)
  (cond
    ((and (realp value) (not (minusp value))) value)
    ((stringp value)
     (handler-case
         (let* ((*read-eval* nil)
                (number (read-from-string value)))
           (and (realp number) (not (minusp number)) number))
       (error () nil)))))

(defun assistant-setting-value (key)
  (let* ((name (%assistant-setting-name key))
         (explicit-p (nth-value 1 (gethash name *assistant-settings*)))
         (raw (if explicit-p
                  (gethash name *assistant-settings*)
                  (%assistant-setting-environment-value name))))
    (cond
      ((string= name "effort") (or raw "low"))
      ((string= name "model") raw)
      ((string= name "max-steps")
       (or (%assistant-parse-positive-integer raw) 10))
      ((string= name "budget")
       (%assistant-parse-budget raw))
      (t nil))))

(defun assistant-setting-explicit-p (key)
  (nth-value 1 (gethash (%assistant-setting-name key) *assistant-settings*)))

(defun set-assistant-setting (key value)
  (let ((name (%assistant-setting-name key)))
    (cond
      ((string= name "effort")
       (if (member (string-downcase (princ-to-string value))
                   '("low" "medium" "high")
                   :test #'string=)
           (progn
             (setf (gethash name *assistant-settings*)
                   (string-downcase (princ-to-string value)))
             (values t nil))
           (values nil "effort must be low, medium, or high")))
      ((string= name "model")
       (if (and (stringp value) (plusp (length value)))
           (progn
             (setf (gethash name *assistant-settings*) value)
             (values t nil))
           (values nil "model must be a non-empty value")))
      ((string= name "max-steps")
       (let ((number (%assistant-parse-positive-integer value)))
         (if number
             (progn
               (setf (gethash name *assistant-settings*) number)
               (values t nil))
             (values nil "max-steps must be a positive integer"))))
      ((string= name "budget")
       (let ((number (%assistant-parse-budget value)))
         (if number
             (progn
               (setf (gethash name *assistant-settings*) number)
               (values t nil))
             (values nil "budget must be a non-negative number"))))
      (t (values nil "unknown setting")))))

(defun reset-assistant-settings ()
  (clrhash *assistant-settings*))

(defun assistant-setting-list ()
  (list (cons "effort" (assistant-setting-value :effort))
        (cons "model" (assistant-setting-value :model))
        (cons "max-steps" (assistant-setting-value :max-steps))
        (cons "budget" (assistant-setting-value :budget))))

(defun assistant-usage-short-text ()
  (let ((budget (assistant-setting-value :budget)))
    (format nil "~dt ~d/~d tokens~a"
            (assistant-usage-turns *assistant-usage*)
            (assistant-usage-input-tokens *assistant-usage*)
            (assistant-usage-output-tokens *assistant-usage*)
            (if budget
                (format nil " budget $~,2f/$~,2f"
                        (assistant-usage-total-cost-usd *assistant-usage*)
                        budget)
                ""))))
