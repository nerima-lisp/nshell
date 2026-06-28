(in-package #:nshell.application)

(defun %builtin-command-path (context args command)
  (let ((spec (%command-path-spec command)))
    (if args
        (let ((exit-code 0))
          (labels ((emit-name (out name)
                     (multiple-value-bind (kind text)
                         (resolve-command-path context name)
                       (case kind
                         (:builtin
                          (format out (getf spec :builtin-format) name)
                          t)
                         (:path
                          (format out (getf spec :path-format) name text)
                          t)
                         (otherwise
                          (write-string
                           (format nil "~a: ~a~%"
                                   (getf spec :missing-prefix)
                                   (format nil (getf spec :missing-format) name))
                           out)
                          nil)))))
            (values
             (with-output-to-string (out)
               (dolist (name args)
                 (unless (emit-name out name)
                   (setf exit-code 1))))
             exit-code)))
        (%builtin-usage command (getf spec :usage)))))

(defun %builtin-type-mode (options)
  (cond
    ((%type-options-query-p options) :query)
    ((%type-options-path-p options) :path)
    ((%type-options-force-path-p options) :force-path)
    ((%type-options-type-p options) :type)
    (t :default)))

(defun %builtin-type-query (context names options)
  (let ((exit-code 1))
    (dolist (name names exit-code)
      (when (%type-command-candidates context name options)
        (setf exit-code 0)))))

(defun %builtin-type-emit-candidate (out spec name candidate options mode)
  (case mode
    (:type
     (format out "~a~%"
             (ecase (first candidate)
               (:alias "alias")
               (:function "function")
               (:abbreviation "abbreviation")
               (:builtin "builtin")
               (:path "file"))))
    (:path
     (case (first candidate)
       (:builtin
        (format out (getf spec :path-builtin-format) name))
       (:path
        (format out (getf spec :path-only-format)
                (second candidate)))))
    (:force-path
     (when (eq (first candidate) :path)
       (format out (getf spec :path-only-format)
               (second candidate))))
    (otherwise
     (%write-type-candidate out spec name candidate options))))

(defun %builtin-type-emit-candidates (out spec name candidates options mode)
  (dolist (candidate (if (%type-options-all-p options)
                         candidates
                         (list (first candidates))))
    (%builtin-type-emit-candidate out spec name candidate options mode)))

(defun %builtin-type-render (context names spec options mode)
  (let ((exit-code 1))
    (values
     (with-output-to-string (out)
       (dolist (name names)
         (let ((candidates (%type-command-candidates context name options)))
           (cond
             (candidates
              (setf exit-code 0)
              (%builtin-type-emit-candidates out spec name candidates options mode))
             ((eq mode :default)
              (write-string (format nil (getf spec :missing-format) name) out))))))
     exit-code)))

(defun %builtin-type (context args)
  (let ((spec nshell.domain.completion:+type-builtin-spec+))
    (multiple-value-bind (options names error error-code)
        (%parse-type-options args)
      (cond
        (error
         (values error error-code))
        ((%type-options-help-p options)
         (%type-usage 0))
        ((null names)
         (%type-usage))
        (t
         (let ((mode (%builtin-type-mode options)))
           (if (eq mode :query)
               (values nil (%builtin-type-query context names options))
               (%builtin-type-render context names spec options mode))))))))

(defun %builtin-which (context args)
  (%builtin-command-path context args "which"))

(defun expand-command-alias-node (command-node alias-table)
  (if (nshell.domain.parsing:command-node-p command-node)
      (let* ((command (nshell.domain.parsing:command-node-command command-node))
             (alias (gethash command alias-table)))
        (if alias
            (nshell.domain.parsing:with-complete-command-line (result alias-node alias)
              (if (nshell.domain.parsing:command-node-p alias-node)
                  (nshell.domain.parsing:make-command-node
                   (nshell.domain.parsing:command-node-command alias-node)
                   (append (nshell.domain.parsing:command-node-args alias-node)
                           (nshell.domain.parsing:command-node-args command-node))
                   nil
                   (nshell.domain.parsing::command-node-command-quote-style alias-node))
                  command-node))
            command-node))
      command-node))

(defun %install-builtin-registry ()
  (clrhash *builtin-registry*)
  (dolist (entry +builtin-registry-specs+)
    (setf (gethash (car entry) *builtin-registry*)
          (symbol-function (cdr entry)))))

(eval-when (:load-toplevel :execute)
  (%install-builtin-registry))
