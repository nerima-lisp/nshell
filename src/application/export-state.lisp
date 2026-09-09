(in-package #:nshell.application)

(defun %assistant-export-git-state (directory)
  (multiple-value-bind (branch dirty-p)
      (nshell.infrastructure.acl:get-git-status directory)
    (list :branch branch :dirty dirty-p)))

(defun %assistant-export-job-listings ()
  (mapcar (lambda (listing)
            (list (cons "id" (job-listing-id listing))
                  (cons "status" (job-listing-status listing))
                  (cons "command" (job-listing-command listing))))
          (jobs)))

(defun %assistant-export-ai-state ()
  (let* ((status
           (nshell.feature.assistant:assistant-boundary-status-snapshot
            (nshell.feature.assistant:assistant-model-boundary)))
         (usage nshell.feature.assistant:*assistant-usage*))
    (list :connected (eq :running (getf status :state))
          :turns (nshell.feature.assistant:assistant-usage-turns usage)
          :tokens (+ (nshell.feature.assistant:assistant-usage-input-tokens usage)
                     (nshell.feature.assistant:assistant-usage-output-tokens usage)))))

(defun export-assistant-transcript
    (&key session-id timestamp cwd text exit duration-ms origin output-head
          denylist-paths denylist-commands denylist-values)
  (nshell.feature.assistant:append-assistant-transcript-entry
   session-id
   (nshell.feature.assistant:make-assistant-transcript-entry
    :timestamp timestamp
    :cwd cwd
    :text text
    :exit exit
    :duration-ms duration-ms
    :origin origin
    :output-head output-head
    :git (%assistant-export-git-state cwd)
    :denylist-paths denylist-paths
    :denylist-commands denylist-commands
    :denylist-values denylist-values)))

(defun export-assistant-snapshot
    (&key session-id cwd last env-names denylist-paths denylist-commands
          denylist-values)
  (nshell.feature.assistant:write-assistant-snapshot
   (nshell.feature.assistant:make-assistant-snapshot
    :cwd cwd
    :git (%assistant-export-git-state cwd)
    :jobs (%assistant-export-job-listings)
    :last last
    :env-names env-names
    :session-id session-id
    :ai (%assistant-export-ai-state)
    :denylist-paths denylist-paths
    :denylist-commands denylist-commands
    :denylist-values denylist-values)))
