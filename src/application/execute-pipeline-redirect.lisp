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

(defun %strip-reader-here-doc-leading-tabs (body)
  (with-output-to-string (output)
    (loop with line-start-p = t
          for character across body
          do (unless (and line-start-p (char= character #\Tab))
               (write-char character output)
               (setf line-start-p (char= character #\Newline))))))

(defun %open-reader-redirect-source
    (context redirect evaluated-target &key avoid-descriptors)
  (let ((kind (nshell.domain.parsing:ast-redirect-entry-kind redirect)))
    (labels ((target-string ()
               (argv-scalar-string
                (nshell.domain.parsing:evaluated-command-arg-value
                 evaluated-target)
                :source-span
                (nshell.domain.parsing:evaluated-command-arg-source-span
                 evaluated-target)))
             (open-file (mode)
               (nshell.infrastructure.acl::open-reader-redirect-file
                (target-string) mode
                :avoid-descriptors avoid-descriptors))
             (open-data (contents)
               (nshell.infrastructure.acl::open-reader-redirect-data
                contents :avoid-descriptors avoid-descriptors)))
      (case kind
        (:input-file (open-file :input))
        ((:output-file :force-output-file :error-file :both-output-files)
         (open-file :output))
        ((:append-output-file :append-error-file :append-both-output-files)
         (open-file :append))
        (:here-string
         (open-data (format nil "~a~%" (target-string))))
        ((:here-document :here-document-strip-tabs)
         (let* ((target
                  (nshell.domain.parsing:ast-redirect-entry-target redirect))
                (body
                  (nshell.domain.parsing:redirect-heredoc-target-body target))
                (body
                  (if (nshell.domain.parsing:redirect-heredoc-target-strip-tabs-p
                       target)
                      (%strip-reader-here-doc-leading-tabs body)
                      body))
                (body
                  (if (nshell.domain.parsing:redirect-heredoc-target-expand-p target)
                      (%expand-here-doc-body-in-context context body)
                      body)))
           (open-data body)))
        (t
         (error "Unsupported reader redirect kind ~S" kind))))))
