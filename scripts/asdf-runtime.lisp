;;;; Shared ASDF runtime configuration for read-only source trees.

(require :asdf)

(defun nshell-configure-writable-asdf-output ()
  "Route compiled systems to a writable directory before loading them."
  (let* ((configured-root (uiop:getenv "NSHELL_ASDF_OUTPUT_DIR"))
         (output-root
           (uiop:ensure-directory-pathname
            (or configured-root
                (merge-pathnames #P"nshell-asdf/"
                                 (uiop:temporary-directory))))))
    (ensure-directories-exist output-root)
    (asdf:initialize-output-translations
     `(:output-translations
       (t ,(truename output-root))
       :ignore-inherited-configuration))
    output-root))

(defun %nshell-register-asd-file (registry source)
  (let ((name (string-downcase (pathname-name source))))
    (unless (gethash name registry)
      (setf (gethash name registry) source))))

(defparameter +nshell-source-registry-exclusions+
  '(".bzr" ".cdv" ".git" ".hg" ".pc" ".svn" "CVS" "RCS" "SCCS"
    "_darcs" "_sgbak" "autom4te.cache" "cover_db" "_build" "debian"))

(defun %nshell-register-asd-directory (registry directory)
  (dolist (source (asdf/source-registry:directory-asd-files directory))
    (%nshell-register-asd-file registry source)))

(defun %nshell-register-asd-tree (registry directory exclusions)
  (asdf/source-registry:collect-sub*directories-asd-files
   directory
   :exclude exclusions
   :collect (lambda (source)
              (%nshell-register-asd-file registry source))))

(defun %nshell-process-source-registry-form (registry form)
  (let ((exclusions (copy-list +nshell-source-registry-exclusions+)))
    (dolist (directive
             (cdr (asdf/source-registry:validate-source-registry-form form)))
      (destructuring-bind (keyword &rest arguments)
          (if (consp directive) directive (list directive))
        (case keyword
          (:directory
           (%nshell-register-asd-directory registry
                                           (uiop:ensure-directory-pathname
                                            (pathname (first arguments)))))
          (:tree
           (%nshell-register-asd-tree registry
                                      (uiop:ensure-directory-pathname
                                       (pathname (first arguments)))
                                      exclusions))
          (:exclude
           (setf exclusions (copy-list arguments)))
          (:also-exclude
           (setf exclusions (append exclusions arguments)))
          ((:ignore-inherited-configuration :inherit-configuration)
           nil)
          (:default-registry
           (error "The nshell source registry cannot include the default registry."))
          (:include
           (error "The nshell source registry cannot include ~S." (first arguments)))
          (otherwise
           (error "Unsupported nshell source-registry directive ~S." keyword)))))))

(defun %nshell-build-source-registry (forms)
  "Build an ASDF registry from FORMS without traversing implementation trees.

ASDF's standard initializer wraps every registry with the implementation's
source tree.  In the Nix shell that tree can contain recursive editor links,
so direct registration is the deterministic project boundary we need here.
Only explicit directories and trees are accepted; inherited and user-level
registries would make a build depend on the host machine."
  (let ((registry (make-hash-table :test #'equal)))
    (dolist (form forms)
      (%nshell-process-source-registry-form registry form))
    registry))

(defun nshell-configure-source-registry (root)
  "Register ROOT and an explicitly requested source tree with ASDF.

An explicit CL_SOURCE_REGISTRY is appended after ROOT so project definitions
win name collisions.  Outside that shell, NSHELL_SOURCE_TREE is opt-in
because a worktree parent can contain many unrelated checkouts and scanning it
makes source discovery both slow and nondeterministic."
  (let* ((root (truename (uiop:ensure-directory-pathname root)))
         (forms (list `(:source-registry
                         (:directory ,root)
                         :ignore-inherited-configuration)))
         (source-registry (uiop:getenv "CL_SOURCE_REGISTRY")))
    (if source-registry
        (setf forms
              (nconc forms
                     (list
                      (asdf/source-registry:parse-source-registry-string
                       source-registry))))
        (let ((source-tree (uiop:getenv "NSHELL_SOURCE_TREE")))
          (when source-tree
            (setf forms
                  (nconc forms
                         (list `(:source-registry
                                  (:tree ,(truename
                                           (uiop:ensure-directory-pathname
                                            source-tree))))))))))
    (setf asdf/source-registry:*source-registry*
          (%nshell-build-source-registry forms))
    root))

(defun nshell-configure-runtime (root)
  "Configure ASDF source lookup and compile policy.

Compiled systems are written beneath NSHELL_ASDF_OUTPUT_DIR when it is set,
or beneath the host temporary directory otherwise.  This is required when the
source tree or its dependencies are read-only, as they are in a Nix build.

SB-POSIX is required here, before the source registry below is replaced with
the project-only tree: cl-host-kit depends on it as a plain ASDF system name
(not a (:require ...) component), and its .asd file lives in SBCL's own
contrib tree, which the replacement registry deliberately excludes."
  (require :sb-posix)
  (let ((root (nshell-configure-source-registry root)))
    (nshell-configure-writable-asdf-output)
    (setf asdf:*compile-file-warnings-behaviour* :warn
          asdf:*compile-file-failure-behaviour* :error)
    root))
