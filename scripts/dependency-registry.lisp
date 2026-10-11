;;;; Keep dependency discovery separate from the editable checkout.

(require :asdf)
(require :sb-posix)

(defparameter *dependency-checkout-root*
  (truename (uiop:pathname-parent-directory-pathname
             (uiop:pathname-directory-pathname *load-truename*))))

(defun dependency-store-path-p (path)
  (and path (uiop:string-prefix-p "/nix/store/" (namestring (truename path)))))

(defun dependency-registry-configuration (value)
  (let* ((registry (and value (asdf/source-registry:parse-source-registry-string value)))
         (entries (and registry (rest registry))))
    (unless (and value (plusp (length value)) (eq (first registry) :source-registry))
      (error "CL_SOURCE_REGISTRY must explicitly name pinned Nix store sources"))
    (setf entries
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
           entries))
    (unless (and entries
                 (every (lambda (entry)
                          (and (consp entry) (member (first entry) '(:directory :tree))
                               (= (length entry) 2)
                               (dependency-store-path-p (second entry))))
                        entries))
      (error "Only explicit Nix store :directory/:tree registry entries are allowed"))
    `(:source-registry ,@entries :ignore-inherited-configuration)))

(defun dependency-configure-registry ()
  (let ((configuration (dependency-registry-configuration (uiop:getenv "CL_SOURCE_REGISTRY"))))
    (setf asdf:*central-registry* nil)
    (asdf:clear-source-registry)
    (asdf:initialize-source-registry configuration)
    ;; Dependency tests that launch child Lisp images inherit the same pins.
    (sb-posix:setenv "CL_SOURCE_REGISTRY" (prin1-to-string configuration) 1)
    configuration))
