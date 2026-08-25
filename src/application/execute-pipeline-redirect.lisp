(in-package #:nshell.application)

;;; Pipeline redirect handling
;;; Functions for extracting, applying, and restoring I/O redirections.
;;; Redirect data is represented as an alist: ((kind . target) ...) where
;;; kind is a keyword (:>, :>>, :&>, :2>, :2>&1, :<, :<<, :<<-, :<<<) and
;;; target is the file path string (or NIL for fd-dup redirects).

;; -- Logic: redirect extraction from command node args ----------------

(defun %extract-command-redirects (cmd-node)
  "Split CMD-NODE args into a command redirect split result.
Redirect args (and their targets) are removed from the args list."
  (nshell.domain.parsing:split-command-node-redirects cmd-node))

(defun %extract-pipeline-redirects (commands)
  "Split COMMANDS into a command-list redirect split result."
  (nshell.domain.parsing:split-command-nodes-redirects commands))

;; -- Logic: context-level redirect application ----------------------

(defun %apply-context-redirects (context redirects)
  "Apply REDIRECTS to the current shell CONTEXT's I/O streams."
  (declare (ignore context))
  (nshell.domain.parsing:map-redirect-entries
   (lambda (kind target)
     (case kind
       (:>    (nshell.infrastructure.acl:redirect-output target :supersede))
       (:>>   (nshell.infrastructure.acl:redirect-output target :append))
       (:&>   (nshell.infrastructure.acl:redirect-output-and-error target :supersede))
       (:&>>  (nshell.infrastructure.acl:redirect-output-and-error target :append))
       (:2>   (nshell.infrastructure.acl:redirect-error target :supersede))
       (:2>>  (nshell.infrastructure.acl:redirect-error target :append))
       (:2>&1 (nshell.infrastructure.acl:redirect-error-to-output))
       (:fd-dup
        (unless (nshell.domain.parsing:redirect-fd-dup-target-p target)
          (error "Missing file-descriptor duplication target"))
        (let ((source (nshell.domain.parsing:redirect-fd-dup-target-source target))
              (destination (nshell.domain.parsing:redirect-fd-dup-target-target target)))
          (cond
            ((and (= source 1) (= destination 2))
             (nshell.infrastructure.acl:redirect-output-to-error))
            ((and (= source 2) (= destination 1))
             (nshell.infrastructure.acl:redirect-error-to-output))
            (t
             (error "Unsupported file-descriptor duplication ~d>&~d"
                    source
                    destination)))))
       (:<    (nshell.infrastructure.acl:redirect-input target))
       (:<<<  (nshell.infrastructure.acl:redirect-input-string target))
       (:<<   (nshell.infrastructure.acl:redirect-input-document target))
       (:<<-  (nshell.infrastructure.acl:redirect-input-document target))
       (t nil)))
   redirects))

(defun %restore-context-redirects (context)
  "Restore I/O streams to their pre-redirect state."
  (declare (ignore context))
  (nshell.infrastructure.acl:restore-redirects))
