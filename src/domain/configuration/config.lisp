;;; Shell configuration entity
(in-package #:nshell.domain.configuration)

(define-value-struct config
    ((theme (default-theme) :type theme)
     (east-asian-ambiguous-width :auto
                                 :type (member :auto :narrow :wide)))
  :documentation "Shell configuration aggregating all settings."
  :constructor %allocate-config
  :predicate %config-p)

(defun parse-east-asian-ambiguous-width (value)
  "Parse the configured ambiguous-width policy, or signal TYPE-ERROR."
  (let ((name (etypecase value
                (symbol (symbol-name value))
                (string value))))
    (cond
      ((string-equal name "auto") :auto)
      ((string-equal name "narrow") :narrow)
      ((string-equal name "wide") :wide)
      (t (error 'type-error :datum value
                :expected-type '(member :auto :narrow :wide))))))

(defun make-config (&key (theme (default-theme))
                         (east-asian-ambiguous-width :auto))
  (check-type theme theme)
  (check-type east-asian-ambiguous-width (member :auto :narrow :wide))
  (%allocate-config theme east-asian-ambiguous-width))

(defun config-p (object)
  "Return true when OBJECT is a configuration aggregate."
  (%config-p object))

(defun default-config ()
  (make-config :theme (default-theme)
               :east-asian-ambiguous-width :auto))
