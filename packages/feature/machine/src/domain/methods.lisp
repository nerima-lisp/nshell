(in-package #:nshell.feature.machine)

;;; The parts of the explain, initialize and policy responses that need no
;;; shell context: converting the classifier's and the knowledge base's
;;; results into envelope parts, and the payloads initialize and policy carry
;;; in the envelope's value.

(defconstant +json-default-timeout-seconds+ 120
  "D-72: the whole-run deadline of --json when --timeout is not given.
initialize announces it.")

(defun %level-name (level)
  (string-downcase (symbol-name level)))

(defun source-span (source start end)
  "Return the ENVELOPE-SPAN of the characters [START, END) of SOURCE: a
1-based line and column, and END as the column after the last character."
  (let* ((start (max 0 (min start (length source))))
         (end (max start (min end (length source))))
         (line-start (let ((newline (position #\Newline source :end start
                                                               :from-end t)))
                       (if newline (1+ newline) 0)))
         (column (1+ (- start line-start))))
    (make-envelope-span :line (1+ (count #\Newline source :end start))
                        :column column
                        :end (+ column (- end start)))))

(defun classification-safety (result)
  "Return the ENVELOPE-SAFETY of the classifier's RESULT: its level and every
(RULE . TEXT) reason it gives at that level."
  (make-envelope-safety
   :level (nshell.feature.assistant:assistant-safety-result-classification result)
   :reasons (mapcar (lambda (reason)
                      (make-envelope-reason :rule (car reason) :text (cdr reason)))
                    (nshell.feature.assistant:assistant-safety-result-reasons result))))

(defun knowledge-base-effects (effects)
  "Return ENVELOPE-EFFECTs for the effect model's EFFECTS: (DELETES PATH),
(WRITES PATH), :NETWORK, and (READS PATH)."
  (mapcar (lambda (effect)
            (let ((kind (intern (symbol-name (if (consp effect) (first effect) effect))
                                :keyword)))
              (unless (member kind +effect-kinds+)
                (%invalid "~S is not an effect kind of the envelope." effect))
              (make-envelope-effect :kind kind
                                    :path (and (consp effect) (second effect)))))
          effects))

(defun initialize-value (&key version methods cwd os
                              (rules (nshell.feature.kb:classify-rule-catalog))
                              (user-rules 0))
  "Return the value of the initialize response (ux/U5): the version, the
implemented METHODS, the limits, a count of the RULES per level, and the
session's CWD and OS."
  (flet ((rules-at (level) (count level rules :key #'second)))
    (json-kit:make-json-object
     (list (cons "version" version)
           (cons "methods" (coerce methods 'vector))
           (cons "limits" (json-kit:make-json-object
                           (list (cons "timeout_s" +json-default-timeout-seconds+))))
           (cons "policy" (json-kit:make-json-object
                           (list (cons "block" (rules-at :block))
                                 (cons "confirm" (rules-at :confirm))
                                 (cons "user_rules" user-rules))))
           (cons "session" (json-kit:make-json-object
                            (list (cons "cwd" cwd)
                                  (cons "os" os)
                                  (cons "attached" json-kit:+json-false+))))))))

(defun policy-value (&key (rules (nshell.feature.kb:classify-rule-catalog))
                          (user-rules 0))
  "Return the value of the policy response (ux/U7): each rule's name, level
and description, and the number of user rules.  A description is null when
the rule takes its text from the input it judges."
  (json-kit:make-json-object
   (list (cons "rules"
               (coerce
                (mapcar (lambda (rule)
                          (destructuring-bind (name level text) rule
                            (json-kit:make-json-object
                             (list (cons "name" name)
                                   (cons "level" (%level-name level))
                                   (cons "description"
                                         (or text json-kit:+json-null+))))))
                        rules)
                'vector))
         (cons "user_rules" user-rules))))
