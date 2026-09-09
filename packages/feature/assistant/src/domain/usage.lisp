(in-package #:nshell.feature.assistant)

(defstruct (assistant-usage-delta
            (:constructor make-assistant-usage-delta
                (&key (turns 1) (input-tokens 0) (output-tokens 0)
                      (total-cost-usd 0))))
  turns
  input-tokens
  output-tokens
  total-cost-usd)

(defun %assistant-usage-field (object key)
  (when (listp object)
    (cdr (assoc key object :test #'string=))))

(defun %assistant-nonnegative-integer (value default)
  (if (and (integerp value) (not (minusp value))) value default))

(defun %assistant-nonnegative-number (value default)
  (if (and (realp value) (not (minusp value))) value default))

(defun assistant-result-usage (payload)
  (let* ((usage (%assistant-usage-field payload "usage"))
         (turns (%assistant-nonnegative-integer
                 (%assistant-usage-field payload "num_turns")
                 1))
         (input-tokens (%assistant-nonnegative-integer
                        (%assistant-usage-field usage "input_tokens")
                        0))
         (output-tokens (%assistant-nonnegative-integer
                         (%assistant-usage-field usage "output_tokens")
                         0))
         (total-cost-usd (%assistant-nonnegative-number
                          (%assistant-usage-field payload "total_cost_usd")
                          0)))
    (make-assistant-usage-delta
     :turns turns
     :input-tokens input-tokens
     :output-tokens output-tokens
     :total-cost-usd total-cost-usd)))

(defun assistant-rate-limit-status (payload)
  (let ((info (%assistant-usage-field payload "rate_limit_info")))
    (and (listp info)
         (let ((status (%assistant-usage-field info "status")))
           (and (stringp status) status)))))
