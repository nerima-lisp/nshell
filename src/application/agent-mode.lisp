(in-package #:nshell.application)

(defconstant +agent-default-max-steps+ 10)

(defvar *agent-start-handler* nil)

(defstruct (agent-step
            (:constructor make-agent-step
                (&key text ast classification status reason output exit-code)))
  text
  ast
  classification
  status
  reason
  output
  exit-code)

(defstruct (agent-session
            (:constructor %make-agent-session
                (task max-steps)))
  task
  max-steps
  (steps-used 0)
  (completed-steps 0)
  current-step
  (state :idle)
  stop-reason)

(defun make-agent-session (task &key (max-steps +agent-default-max-steps+))
  (check-type task string)
  (check-type max-steps (integer 1 *))
  (%make-agent-session task max-steps))

(defun agent-step-blocked-p (step)
  (and step
       (agent-step-classification step)
       (eq :block
           (nshell.feature.assistant:assistant-safety-result-classification
            (agent-step-classification step)))))

(defun agent-step-executable-p (step)
  (and step
       (agent-step-ast step)
       (agent-step-classification step)
       (not (agent-step-blocked-p step))))

(defun %agent-step-from-text (text)
  (let ((result (nshell.domain.parsing:parse-command-line text)))
    (if (and (nshell.domain.parsing:parse-complete-p result)
             (nshell.domain.parsing:parse-result-ast result))
        (let ((ast (nshell.domain.parsing:parse-result-ast result)))
          (make-agent-step
           :text text
           :ast ast
           :classification (nshell.feature.assistant:classify-ast ast)
           :status :awaiting-approval))
        (make-agent-step
         :text text
         :status :parse-error
         :reason "agent: proposed command could not be parsed"))))

(defun agent-session-propose-step (session text)
  (check-type session agent-session)
  (check-type text string)
  (when (agent-session-limit-reached-p session)
    (agent-session-stop session "maximum step count reached")
    (return-from agent-session-propose-step nil))
  (incf (agent-session-steps-used session))
  (setf (agent-session-current-step session)
        (%agent-step-from-text text)
        (agent-session-state session) :awaiting-approval)
  (agent-session-current-step session))

(defun agent-session-reclassify-step (session text)
  (check-type session agent-session)
  (check-type text string)
  (when (agent-session-current-step session)
    (setf (agent-session-current-step session)
          (%agent-step-from-text text)
          (agent-session-state session) :awaiting-approval))
  (agent-session-current-step session))

(defun %agent-interrupted-exit-p (exit-code)
  (eql exit-code 130))

(defun agent-session-record-step (session output exit-code)
  (check-type session agent-session)
  (let ((step (agent-session-current-step session)))
    (when step
      (setf (agent-step-output step) output
            (agent-step-exit-code step) exit-code
            (agent-step-status step)
              (if (%agent-interrupted-exit-p exit-code)
                  :interrupted
                  :executed))
      (incf (agent-session-completed-steps session))
      (setf (agent-session-current-step session) nil
            (agent-session-state session) :requesting)
      step)))

(defun agent-session-skip-step (session)
  (check-type session agent-session)
  (let ((step (agent-session-current-step session)))
    (when step
      (setf (agent-step-status step) :skipped)
      (incf (agent-session-completed-steps session))
      (setf (agent-session-current-step session) nil
            (agent-session-state session) :requesting)
      step)))

(defun agent-session-stop (session reason)
  (check-type session agent-session)
  (setf (agent-session-state session) :stopped
        (agent-session-stop-reason session) reason
        (agent-session-current-step session) nil)
  session)

(defun agent-session-limit-reached-p (session)
  (>= (agent-session-steps-used session)
      (agent-session-max-steps session)))

(defun %agent-max-steps-value (value)
  (cond
    ((and (integerp value) (plusp value)) value)
    ((and (stringp value) (plusp (length value)))
     (handler-case
         (let ((number (parse-integer value :junk-allowed nil)))
           (and (plusp number) number))
       (error () nil)))))

(defun agent-max-steps-from-context (context)
  (if (nshell.feature.assistant:assistant-setting-explicit-p :max-steps)
      (or (%agent-max-steps-value
           (nshell.feature.assistant:assistant-setting-value :max-steps))
          +agent-default-max-steps+)
      (or (%agent-max-steps-value
           (and (shell-context-environment context)
                (nshell.domain.environment:env-get
                 (shell-context-environment context)
                 "NSHELL_AI_MAX_STEPS")))
          +agent-default-max-steps+)))
