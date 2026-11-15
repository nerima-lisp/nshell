;;;; Keep dependency discovery separate from the editable checkout.

(require :asdf)
(require :sb-posix)

(defparameter *dependency-checkout-root*
  (truename (uiop:pathname-parent-directory-pathname
             (uiop:pathname-directory-pathname *load-truename*))))

(defun dependency-store-path-p (path)
  (and path (uiop:string-prefix-p "/nix/store/" (namestring (truename path)))))

(defun dependency-registry-configuration (value &optional extra-value)
  (labels ((parse-registry-entries (source variable)
             (let ((registry
                     (handler-case
                         (and source (asdf/source-registry:parse-source-registry-string source))
                       (asdf/source-registry:invalid-source-registry ()
                         (error "~A must explicitly name pinned Nix store sources" variable)))))
               (unless (and source (plusp (length source))
                            (eq (first registry) :source-registry))
                 (error "~A must explicitly name pinned Nix store sources" variable))
               (remove-if
                (lambda (entry)
                  (or (member entry '(:inherit-configuration :ignore-inherited-configuration
                                      (:inherit-configuration) (:ignore-inherited-configuration))
                              :test #'equal)
                      ;; The forge dev shell prepends its checkout. Never use it
                      ;; when resolving the pinned libraries' own test systems.
                      (and (consp entry) (eq (first entry) :directory) (= (length entry) 2)
                           (equal *dependency-checkout-root*
                                  (truename (uiop:ensure-directory-pathname (second entry)))))))
                (rest registry))))
           (store-registry-entry-p (entry)
             (and (consp entry) (member (first entry) '(:directory :tree))
                  (= (length entry) 2)
                  (dependency-store-path-p (second entry))))
           (check-store-registry-entries (entries variable)
             (unless (every #'store-registry-entry-p entries)
               (error "~A may only name explicit Nix store :directory/:tree registry entries"
                      variable))))
    (let* ((entries (parse-registry-entries value "CL_SOURCE_REGISTRY"))
           (extra-entries (and extra-value
                               (parse-registry-entries
                                extra-value "NSHELL_DEPENDENCY_SOURCE_REGISTRY"))))
      (check-store-registry-entries entries "CL_SOURCE_REGISTRY")
      (when extra-value
        (check-store-registry-entries extra-entries "NSHELL_DEPENDENCY_SOURCE_REGISTRY")
        (setf entries (append entries extra-entries)))
      (unless entries
        (error "CL_SOURCE_REGISTRY~@[ and NSHELL_DEPENDENCY_SOURCE_REGISTRY~] must include pinned Nix store sources"
               extra-value))
      (cons :source-registry (append entries '(:ignore-inherited-configuration))))))


(defun dependency-configure-registry ()
  (let ((configuration (dependency-registry-configuration
                        (uiop:getenv "CL_SOURCE_REGISTRY")
                        (uiop:getenv "NSHELL_DEPENDENCY_SOURCE_REGISTRY"))))
    (setf asdf:*central-registry* nil)
    (asdf:clear-source-registry)
    (asdf:initialize-source-registry configuration)
    ;; Dependency tests that launch child Lisp images inherit the same pins.
    (sb-posix:setenv "CL_SOURCE_REGISTRY" (prin1-to-string configuration) 1)
    configuration))
