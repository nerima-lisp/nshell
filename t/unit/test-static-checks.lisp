(in-package #:nshell/test)

;; Consume #. data without evaluation so the surrounding form remains readable.
(defun static-check-skip-reader-eval (stream sub-character argument)
  (declare (ignore sub-character argument))
  (read stream t nil t)
  :static-check-reader-eval-placeholder)

(progn
  (defparameter +static-check-layer-rules+
    '((:domain :application :infrastructure :presentation)
      (:application :presentation)
      (:infrastructure :application :presentation)))
  (defparameter +static-check-definition-operators+
    '("DEFUN" "DEFMACRO"
              "DEFGENERIC"
              "DEFMETHOD"
              "DEFPARAMETER"
              "DEFVAR"
              "DEFCONSTANT"
              "DEFCLASS"
              "DEFTYPE"
              "DEFINE-CONDITION"
              "DEFSTRUCT"
              "DEFINE-VALUE-STRUCT"))
  (defparameter +static-check-test-declaration-operators+
    '("IT" "IT-EACH" "IT-FAILS" "DESCRIBE" "DESCRIBE-EACH"))
  (defun static-check-form-operator-name (form)
    (when (and (consp form) (symbolp (first form)))
      (string-upcase (symbol-name (first form)))))
  (defun static-check-project-root ()
    (uiop:pathname-directory-pathname
     (asdf:system-source-file (asdf:find-system "nshell"))))
  (defun static-check-split-path (text)
    (let ((separator (position #\/ text)))
      (if separator
          (cons (subseq text 0 separator)
                (static-check-split-path (subseq text (1+ separator))))
          (list text))))
  (defun static-check-relative-path (pathname root)
    (enough-namestring (truename pathname)
                       (uiop:ensure-directory-pathname root)))
  (defun static-check-lisp-files-under (directory)
    (labels ((walk (directory)
               (append
                (remove-if-not
                 (lambda (pathname)
                   (and (pathname-type pathname)
                        (string-equal (pathname-type pathname) "lisp")))
                 (uiop:directory-files directory))
                (mapcan #'walk (uiop:subdirectories directory)))))
      (sort
       (mapcar #'truename (walk (uiop:ensure-directory-pathname directory)))
       #'string<
       :key
       #'namestring)))
  (defun static-check-discovered-lisp-files (root)
    (mapcan
     (lambda (directory)
       (static-check-lisp-files-under (merge-pathnames directory root)))
     '("src/" "packages/" "t/")))
  (defun static-check-system-source-paths (system)
    (labels ((visit (component)
               (append
                (when
                    (and (pathname-type (asdf:component-pathname component))
                         (string-equal
                          (pathname-type (asdf:component-pathname component))
                          "lisp"))
                  (list (truename (asdf:component-pathname component))))
                (when (typep component 'asdf:module)
                  (mapcan #'visit (asdf:component-children component))))))
      (visit (asdf:find-system system))))
  (defun static-check-registered-lisp-files (root)
    (remove-duplicates
     (mapcar
      (lambda (pathname)
        (static-check-relative-path pathname root))
      (append (static-check-system-source-paths "nshell")
              (static-check-system-source-paths "nshell/test")
              (static-check-system-source-paths "nshell/weave")))
     :test
     #'string=))
  (defun static-check-unregistered-files-from-paths (discovered registered)
    (sort (set-difference discovered registered :test #'string=) #'string<))
  (defun static-check-unregistered-lisp-files (&optional
                                               (root
                                                (static-check-project-root)))
    (static-check-unregistered-files-from-paths
     (mapcar
      (lambda (pathname)
        (static-check-relative-path pathname root))
      (static-check-discovered-lisp-files root))
     (static-check-registered-lisp-files root)))
  (defun static-check-read-forms (pathname)
    (with-open-file (stream pathname :direction :input :external-format :utf-8)
      (let ((*read-eval* nil)
            (*readtable* (copy-readtable nil))
            (*package* (find-package "CL-USER"))
            (forms nil))
        (set-dispatch-macro-character #\# #\. #'static-check-skip-reader-eval)
        (loop for form = (read stream nil :eof)
              until (eq form :eof)
              do (progn
                   (when
                       (string= (or (static-check-form-operator-name form) "")
                                "IN-PACKAGE")
                     (let* ((designator (second form))
                            (name
                             (if (symbolp designator)
                                 (symbol-name designator)
                                 designator))
                            (package (and (stringp name) (find-package name))))
                       (unless package
                         (error "Unknown package ~s while reading ~a."
                                name
                                pathname))
                       (setf *package* package)))
                   (push form forms)))
        (nreverse forms))))
  (defun static-check-top-level-forms-named (form operator-name)
    (let ((operator (static-check-form-operator-name form)))
      (cond
        ((member operator '("QUOTE" "FUNCTION") :test #'string=) nil)
        ((string= (or operator "") operator-name) (list form))
        ((string= (or operator "") "EVAL-WHEN")
         (mapcan
          (lambda (child)
            (static-check-top-level-forms-named child operator-name))
          (cddr form)))
        ((string= (or operator "") "PROGN")
         (mapcan
          (lambda (child)
            (static-check-top-level-forms-named child operator-name))
          (cdr form)))
        (t nil))))
  (defun static-check-layer-from-package-name (package-name)
    (when package-name
      (let ((name (string-upcase package-name)))
        (loop for layer in '(:domain :application :infrastructure :presentation)
              for prefix = (concatenate 'string
                                        "NSHELL."
                                        (string-upcase (symbol-name layer)))
              when (and (<= (length prefix) (length name))
                        (string= prefix name :end2 (length prefix))
                        (or (= (length prefix) (length name))
                            (char= #\. (char name (length prefix)))))
                return layer))))
  (defun static-check-layer-from-path (pathname root)
    (let* ((relative (static-check-relative-path pathname root))
           (segments (static-check-split-path relative))
           (file-name (string-downcase (pathname-name pathname))))
      (or
       (loop for layer in '(:domain :application :infrastructure :presentation)
             for segment = (string-downcase (symbol-name layer))
             when (or
                   (string= file-name (concatenate 'string "package-" segment))
                   (member segment segments :test #'string=))
               return layer)
       nil)))
  (defun static-check-layer-forbidden-p (source target)
    (member target (cdr (assoc source +static-check-layer-rules+)) :test #'eq))
  (defun static-check-symbol-layer (symbol definitions)
    (let* ((package (symbol-package symbol))
           (package-name (and package (package-name package)))
           (package-layer (static-check-layer-from-package-name package-name)))
      (or package-layer
          (when
              (and package-name
                   (>= (length package-name) (length "NSHELL.FEATURE."))
                   (string= "NSHELL.FEATURE."
                            package-name
                            :end2
                            (length "NSHELL.FEATURE.")))
            (let ((layers
                   (gethash (list package-name (symbol-name symbol))
                            definitions)))
              (when (= (length layers) 1)
                (first layers)))))))
  (defun static-check-feature-definition-map (files root)
    (labels ((register-name (package name layer definitions)
               (let ((package-name (and package (package-name package))))
                 (when
                     (and package-name
                          (stringp name)
                          (>= (length package-name) (length "NSHELL.FEATURE."))
                          (string= "NSHELL.FEATURE."
                                   package-name
                                   :end2
                                   (length "NSHELL.FEATURE.")))
                   (pushnew layer
                            (gethash (list package-name name) definitions)
                            :test
                            #'eq))))
             (register-symbol (symbol layer definitions)
               (when (symbolp symbol)
                 (register-name (symbol-package symbol)
                                (symbol-name symbol)
                                layer
                                definitions)))
             (structure-option (options name)
               (find-if
                (lambda (option)
                  (and (consp option) (eq (first option) name)))
                options))
             (structure-slot-name (slot)
               (if (consp slot)
                   (first slot)
                   slot))
             (defstruct-generated-names (form)
               (let* ((name-spec (second form))
                      (name
                       (if (consp name-spec)
                           (first name-spec)
                           name-spec))
                      (options
                       (if (consp name-spec)
                           (rest name-spec)
                           nil))
                      (body (cddr form))
                      (slots
                       (if (stringp (first body))
                           (rest body)
                           body))
                      (conc-name-option (structure-option options :conc-name))
                      (conc-name
                       (if conc-name-option
                           (let ((value (second conc-name-option)))
                             (cond
                               ((null value) "")
                               ((symbolp value) (symbol-name value))
                               (t value)))
                           (format nil "~a-" (symbol-name name))))
                      (constructor-options
                       (remove-if-not
                        (lambda (option)
                          (and (consp option) (eq (first option) :constructor)))
                        options))
                      (predicate-option (structure-option options :predicate))
                      (copier-option (structure-option options :copier)))
                 (append (list (symbol-name name))
                         (mapcar
                          (lambda (slot)
                            (concatenate 'string
                                         conc-name
                                         (symbol-name (structure-slot-name slot))))
                          (remove-if-not
                           (lambda (slot)
                             (symbolp (structure-slot-name slot)))
                           slots))
                         (if constructor-options
                             (loop for option in constructor-options
                                   when (symbolp (second option))
                                     collect (symbol-name (second option)))
                             (list (format nil "MAKE-~a" (symbol-name name))))
                         (if predicate-option
                             (if (symbolp (second predicate-option))
                                 (list (symbol-name (second predicate-option)))
                                 nil)
                             (list (format nil "~a-P" (symbol-name name))))
                         (if copier-option
                             (if (symbolp (second copier-option))
                                 (list (symbol-name (second copier-option)))
                                 nil)
                             (list (format nil "COPY-~a" (symbol-name name)))))))
             (register-definition-forms (form layer definitions)
               (dolist (operator +static-check-definition-operators+)
                 (dolist
                     (definition
                      (static-check-top-level-forms-named form operator))
                   (let* ((name-spec (second definition))
                          (name
                           (if (consp name-spec)
                               (first name-spec)
                               name-spec))
                          (package (and (symbolp name) (symbol-package name))))
                     (register-symbol name layer definitions)
                     (when (and package (string= operator "DEFSTRUCT"))
                       (dolist
                           (generated-name (defstruct-generated-names definition))
                         (register-name package generated-name layer definitions)))
                     (when
                         (and package
                              (string= operator "DEFINE-VALUE-STRUCT")
                              (>= (length (package-name package))
                                  (length "NSHELL.FEATURE."))
                              (string= "NSHELL.FEATURE."
                                       (package-name package)
                                       :end2
                                       (length "NSHELL.FEATURE.")))
                       (let ((*package* package))
                         (register-definition-forms (macroexpand-1 definition)
                                                    layer
                                                    definitions))))))))
      (let ((definitions (make-hash-table :test #'equal)))
        (dolist (pathname files definitions)
          (let ((layer (static-check-layer-from-path pathname root)))
            (when layer
              (dolist (form (static-check-read-forms pathname))
                (register-definition-forms form layer definitions))))))))
  (defun static-check-layer-reference-keys-in-form (form source-layer definitions)
    (labels ((walk-list (tail)
               (if (consp tail)
                   (append (walk (car tail)) (walk-list (cdr tail)))
                   (walk tail)))
             (walk (node)
               (cond
                 ((symbolp node)
                  (let ((target-layer
                         (static-check-symbol-layer node definitions)))
                    (when
                        (and target-layer
                             (static-check-layer-forbidden-p source-layer
                                                             target-layer))
                      (list (list target-layer (symbol-name node))))))
                 ((consp node)
                  (unless
                      (member (static-check-form-operator-name node)
                              '("QUOTE" "DEFPACKAGE")
                              :test
                              #'string=)
                    (walk-list node)))
                 (t nil))))
      (walk form)))
  (defun static-check-package-designator-name (designator)
    (string-upcase
     (if (symbolp designator)
         (symbol-name designator)
         designator)))
  (defun static-check-package-layer-edges (form source-layer)
    (let* ((package-name (static-check-package-designator-name (second form)))
           (caller-layer
            (or (static-check-layer-from-package-name package-name)
                source-layer))
           (edges nil))
      (when caller-layer
        (dolist (option (cddr form))
          (let* ((option-name (static-check-form-operator-name option))
                 (packages
                  (cond
                    ((member option-name '("USE") :test #'string=) (cdr option))
                    ((member option-name
                             '("IMPORT-FROM" "SHADOWING-IMPORT-FROM")
                             :test
                             #'string=) (list (second option))))))
            (dolist (designator packages)
              (let* ((target-name
                      (static-check-package-designator-name designator))
                     (target-layer
                      (static-check-layer-from-package-name target-name)))
                (when
                    (and target-layer
                         (static-check-layer-forbidden-p caller-layer
                                                         target-layer))
                  (push
                   (list target-layer
                         (concatenate 'string "PACKAGE:" target-name))
                   edges))))))
        edges)))
  (defun static-check-record-layer-edge (table path source target symbol-name)
    (incf (gethash (list path source target symbol-name) table 0)))
  (defun static-check-layer-violations (&optional
                                        (root (static-check-project-root)))
    (let* ((files (static-check-lisp-files-under (merge-pathnames "src/" root)))
           (files
            (append files
                    (static-check-lisp-files-under
                     (merge-pathnames "packages/" root))))
           (definitions (static-check-feature-definition-map files root))
           (counts (make-hash-table :test #'equal)))
      (dolist (pathname files)
        (let ((source-layer (static-check-layer-from-path pathname root))
              (relative (static-check-relative-path pathname root)))
          (when source-layer
            (dolist (form (static-check-read-forms pathname))
              (dolist
                  (package-form
                   (static-check-top-level-forms-named form "DEFPACKAGE"))
                (dolist
                    (edge
                     (static-check-package-layer-edges package-form
                                                       source-layer))
                  (static-check-record-layer-edge counts
                                                  relative
                                                  source-layer
                                                  (first edge)
                                                  (second edge))))
              (dolist
                  (edge
                   (static-check-layer-reference-keys-in-form form
                                                              source-layer
                                                              definitions))
                (static-check-record-layer-edge counts
                                                relative
                                                source-layer
                                                (first edge)
                                                (second edge)))))))
      (sort
       (loop for key being the hash-keys of counts using (hash-value count)
             collect (append key (list count)))
       #'string<
       :key
       #'prin1-to-string)))
  (progn
    (defun static-check-allowlist-entries (key)
      (getf +static-check-allowlist+ key))
    (defun static-check-expected-unregistered-lisp-files ()
      (sort
       (loop for entry in (static-check-allowlist-entries
                           :unregistered-lisp-files)
             for required-feature = (getf (cddr entry) :unless-feature)
             unless (and required-feature (member required-feature *features*))
               collect (first entry))
       #'string<)))
  (defun static-check-allowlist-reasons-present-p ()
    (and
     (every
      (lambda (entry)
        (and (or (= (length entry) 2) (= (length entry) 4))
             (stringp (first entry))
             (stringp (second entry))
             (plusp (length (second entry)))
             (or (= (length entry) 2)
                 (and (eq (third entry) :unless-feature)
                      (keywordp (fourth entry))))))
      (static-check-allowlist-entries :unregistered-lisp-files))
     (every
      (lambda (entry)
        (and (= (length entry) 6)
             (stringp (first entry))
             (keywordp (second entry))
             (keywordp (third entry))
             (stringp (fourth entry))
             (integerp (fifth entry))
             (plusp (fifth entry))
             (stringp (sixth entry))
             (plusp (length (sixth entry)))))
      (static-check-allowlist-entries :layer-violations))
     (every
      (lambda (entry)
        (and (= (length entry) 2)
             (stringp (first entry))
             (stringp (second entry))
             (plusp (length (second entry)))))
      (static-check-allowlist-entries :builtin-document-omissions))))
  (defun static-check-builtin-source-names (&optional
                                            (root (static-check-project-root)))
    (let* ((pathname
            (merge-pathnames "data/application/builtin-spec-data.lisp" root))
           (definition
            (find-if
             (lambda (form)
               (and
                (string= (or (static-check-form-operator-name form) "")
                         "DEFPARAMETER")
                (symbolp (second form))
                (string= (symbol-name (second form)) "+BUILTIN-REGISTRY-SPECS+")))
             (static-check-read-forms pathname)))
           (value (third definition)))
      (unless
          (and definition
               (consp value)
               (string= (or (static-check-form-operator-name value) "") "QUOTE"))
        (error "Could not read +builtin-registry-specs+ from ~a." pathname))
      (let ((names (mapcar #'first (second value))))
        (unless (every #'stringp names)
          (error "Builtin registry entries must begin with strings."))
        (when
            (/= (length names)
                (length (remove-duplicates names :test #'string=)))
          (error "Builtin registry contains duplicate names."))
        names)))
  (defun static-check-builtin-document-names (&optional
                                              (root (static-check-project-root)))
    (let* ((pathname (merge-pathnames "docs/src/reference/builtins.md" root))
           (text (uiop:read-file-string pathname))
           (start (search "`agent`" text))
           (end
            (and start (search "## Notes on a few of them" text :start2 start))))
      (unless (and start end)
        (error "Could not locate the builtin inventory in ~a." pathname))
      (loop with cursor = start
            for opening = (position #\` text :start cursor)
            while (and opening (< opening end))
            for closing = (position #\` text :start (1+ opening))
            while (and closing (< closing end))
            collect (subseq text (1+ opening) closing)
            do (setf cursor (1+ closing)))))
  (defun static-check-sort-strings (strings)
    (sort (copy-list strings) #'string<))
  (defun static-check-builtin-document-diff (source-names document-names)
    (list :missing-from-documentation
          (static-check-sort-strings
           (set-difference source-names document-names :test #'string=))
          :unknown-in-documentation
          (static-check-sort-strings
           (set-difference document-names source-names :test #'string=))))
  (defun static-check-suite-source-p (pathname root)
    (let ((segments
           (static-check-split-path (static-check-relative-path pathname root))))
      (and (string= (first segments) "t")
           (not
            (member (second segments)
                    '("support" "scripts" "package.lisp" "helpers-runner.lisp")
                    :test
                    #'string=)))))
  (defun static-check-nested-test-sites-in-form (form pathname)
    (labels ((walk-list (tail inside-test-p)
               (if (consp tail)
                   (append (walk (car tail) inside-test-p)
                           (walk-list (cdr tail) inside-test-p))
                   (walk tail inside-test-p)))
             (walk (node inside-test-p)
               (when (consp node)
                 (let* ((operator (static-check-form-operator-name node))
                        (declaration-p
                         (member operator
                                 +static-check-test-declaration-operators+
                                 :test
                                 #'string=))
                        (test-p
                         (member operator
                                 '("IT" "IT-EACH" "IT-FAILS")
                                 :test
                                 #'string=)))
                   (unless (string= (or operator "") "QUOTE")
                     (append
                      (when (and inside-test-p declaration-p)
                        (list (list pathname operator)))
                      (walk-list (cdr node) (or inside-test-p test-p))))))))
      (walk form nil)))
  (defun static-check-nested-test-sites (&optional
                                         (root (static-check-project-root)))
    (let ((files
           (remove-if-not
            (lambda (pathname)
              (static-check-suite-source-p pathname root))
            (static-check-lisp-files-under (merge-pathnames "t/" root)))))
      (sort
       (loop for pathname in files
             for relative = (static-check-relative-path pathname root)
             append (mapcan
                     (lambda (form)
                       (static-check-nested-test-sites-in-form form relative))
                     (static-check-read-forms pathname)))
       #'string<
       :key
       #'prin1-to-string)))
  (defun static-check-reasoned-layer-allowlist-keys ()
    (sort
     (mapcar
      (lambda (entry)
        (subseq entry 0 5))
      (static-check-allowlist-entries :layer-violations))
     #'string<
     :key
     #'prin1-to-string)))

(describe "static repository checks"
          (it "finds every unregistered Lisp file under the source roots"
              (let ((expected (static-check-expected-unregistered-lisp-files)))
                (expect (static-check-allowlist-reasons-present-p) :to-equal t)
                (expect (static-check-unregistered-lisp-files) :to-equal expected)
                (expect
                 (static-check-unregistered-files-from-paths
                  '("src/registered.lisp" "t/unregistered-fixture.lisp")
                  '("src/registered.lisp"))
                 :to-equal
                 '("t/unregistered-fixture.lisp"))))
          (it "enforces layer dependencies and accounts for known references"
              (let* ((expected (static-check-reasoned-layer-allowlist-keys))
                     (actual (static-check-layer-violations))
                     (root (static-check-project-root))
                     (feature-files
                       (static-check-lisp-files-under
                        (merge-pathnames "packages/feature/" root)))
                     (definitions (static-check-feature-definition-map feature-files root))
                     (presentation
                       (find-symbol "HIGHLIGHT-LINE"
                                    (find-package "NSHELL.PRESENTATION")))
                     (assistant-setting
                       (find-symbol "ASSISTANT-SETTING-VALUE"
                                    (find-package "NSHELL.FEATURE.ASSISTANT")))
                     (assistant-context-command
                       (find-symbol "ASSISTANT-CONTEXT-COMMAND"
                                    (find-package "NSHELL.FEATURE.ASSISTANT")))
                     (terminal-api
                       (find-symbol "ANSI-RESET-STYLE"
                                    (find-package "NSHELL.INFRASTRUCTURE.TERMINAL"))))
                (expect (static-check-allowlist-reasons-present-p) :to-equal t)
                (expect actual :to-equal expected)
                (expect
                 (gethash '("NSHELL.FEATURE.ASSISTANT" "ASSISTANT-SETTING-VALUE")
                          definitions)
                 :to-equal
                 '(:application))
                (expect
                 (gethash '("NSHELL.FEATURE.ASSISTANT" "ASSISTANT-CONTEXT-COMMAND")
                          definitions)
                 :to-equal
                 '(:domain))
                (expect
                 (static-check-layer-reference-keys-in-form
                  (list presentation)
                  :application
                  definitions)
                 :to-equal
                 '((:presentation "HIGHLIGHT-LINE")))
                (expect
                 (static-check-layer-reference-keys-in-form
                  (list assistant-setting)
                  :infrastructure
                  definitions)
                 :to-equal
                 '((:application "ASSISTANT-SETTING-VALUE")))
                (expect
                 (static-check-layer-reference-keys-in-form
                  (list assistant-context-command)
                  :infrastructure
                  definitions)
                 :to-equal
                 nil)
                (expect
                 (static-check-symbol-layer assistant-context-command definitions)
                 :to-equal
                 :domain)
                (expect
                 (static-check-layer-reference-keys-in-form
                  (list presentation)
                  :presentation
                  definitions)
                 :to-equal
                 nil)
                (expect (static-check-symbol-layer terminal-api definitions)
                        :to-equal
                        :infrastructure)
                (expect
                 (static-check-layer-reference-keys-in-form
                  (list terminal-api)
                  :presentation
                  definitions)
                 :to-equal
                 nil)
                (expect
                 (static-check-package-layer-edges
                  '(defpackage #:nshell.application.fixture
                    (:import-from #:nshell.presentation #:highlight-line))
                  :application)
                 :to-equal
                 '((:presentation "PACKAGE:NSHELL.PRESENTATION")))))
          (it "matches the builtin registry to the documented inventory"
              (let* ((source (static-check-builtin-source-names))
                     (documented (static-check-builtin-document-names))
                     (diff (static-check-builtin-document-diff source documented))
                     (omissions
                      (mapcar #'first
                              (static-check-allowlist-entries :builtin-document-omissions))))
                (expect (static-check-allowlist-reasons-present-p) :to-equal t)
                (expect
                 (= (length source) (length (remove-duplicates source :test #'string=)))
                 :to-be-truthy)
                (expect
                 (= (length documented)
                    (length (remove-duplicates documented :test #'string=)))
                 :to-be-truthy)
                (expect (getf diff :missing-from-documentation) :to-equal omissions)
                (expect (getf diff :unknown-in-documentation) :to-equal nil)
                (expect
                 (static-check-builtin-document-diff '("echo" "new-command") '("echo"))
                 :to-equal
                 '(:missing-from-documentation ("new-command")
                                               :unknown-in-documentation
                                               nil))))
          (it "rejects test declarations nested inside an it body"
              (expect (static-check-nested-test-sites) :to-equal nil)
              (expect
               (static-check-nested-test-sites-in-form
                '(describe "root"
                           (it "outer suite" (describe "nested" (it "inner" nil)))
                           (it "outer test" (it "nested test" nil)))
                "fixture.lisp")
               :to-equal
               '(("fixture.lisp" "DESCRIBE") ("fixture.lisp" "IT") ("fixture.lisp" "IT")))))
