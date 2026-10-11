(load (merge-pathnames "dependency-registry.lisp" *load-truename*))

(let* ((original (uiop:getenv "CL_SOURCE_REGISTRY"))
       (parsed (asdf/source-registry:parse-source-registry-string original))
       (stores (remove-if-not
                (lambda (entry)
                  (and (consp entry) (member (first entry) '(:directory :tree))
                       (= (length entry) 2) (dependency-store-path-p (second entry))))
                (rest parsed)))
       (checkout (namestring *dependency-checkout-root*))
       (parent (namestring (uiop:pathname-parent-directory-pathname *dependency-checkout-root*)))
       (child (namestring (merge-pathnames "scripts/" *dependency-checkout-root*)))
       (passed 0))
  (unless stores (error "Registry regression tests require nonempty Nix store fixtures"))
  (labels ((check (name result)
             (unless result (error "Registry check failed: ~A" name))
             (incf passed)
             (format t "registry-check ~A PASS~%" name))
           (configuration (&rest entries)
             (dependency-registry-configuration
              (prin1-to-string `(:source-registry ,@entries :ignore-inherited-configuration))))
           (rejects (value)
             (handler-case (progn (dependency-registry-configuration value) nil)
               (asdf/source-registry:invalid-source-registry () t)
               (error () t))))
    (let ((expected `(:source-registry ,@stores :ignore-inherited-configuration)))
      (check "store-order" (equal expected (apply #'configuration stores)))
      (check "checkout-removed"
             (equal expected (apply #'configuration `(:directory ,checkout) stores)))
      (check "colon-devshell"
             (equal `(:source-registry (:directory ,(second (first stores)))
                       :ignore-inherited-configuration)
                    (dependency-registry-configuration
                     (format nil "~A:~A" checkout (second (first stores))))))
      (check "store-tree"
             (equal `(:source-registry (:tree ,(second (first stores)))
                       :ignore-inherited-configuration)
                    (configuration `(:tree ,(second (first stores))))))
      (check "inheritance-removed"
             (equal expected (dependency-registry-configuration
                              (prin1-to-string
                               `(:source-registry ,@stores :inherit-configuration)))))
      (uiop:with-current-directory (child)
        (check "checkout-independent-of-cwd"
               (equal expected (apply #'configuration `(:directory ,checkout) stores))))
      (dolist (entry `((:directory ,parent) (:directory ,child) (:tree ,checkout)
                       (:include ,checkout) (:directory ,checkout :extra)))
        (check (format nil "reject-~S" (first entry))
               (rejects (prin1-to-string
                         `(:source-registry ,entry ,@stores :ignore-inherited-configuration)))))
      (check "checkout-only-rejected"
             (rejects (prin1-to-string `(:source-registry (:directory ,checkout)
                                         :ignore-inherited-configuration))))
      (check "empty-rejected" (rejects ""))
      (check "unset-rejected" (rejects nil))
      (sb-posix:setenv "CL_SOURCE_REGISTRY" original 1)
      (check "configured-store-only" (equal expected (dependency-configure-registry)))
      (check "exported-store-only"
             (equal expected (read-from-string (uiop:getenv "CL_SOURCE_REGISTRY"))))
      (check "child-inherits-store-only"
             (equal expected
                    (read-from-string
                     (uiop:run-program
                      (list (namestring sb-ext:*runtime-pathname*) "--noinform" "--non-interactive"
                            "--eval" "(require :asdf)"
                            "--eval" "(write-string (uiop:getenv \"CL_SOURCE_REGISTRY\"))")
                      :output :string))))
      (uiop:with-temporary-file (:pathname shadow :type "asd" :prefix "nshell-registry-shadow-"
                                :stream stream)
        (let ((name (pathname-name shadow)))
          (format stream "(asdf:defsystem ~S)~%" name)
          (finish-output stream)
          (setf asdf:*central-registry* (list (uiop:pathname-directory-pathname shadow)))
          (check "local-shadow-control" (asdf:find-system name nil))
          (asdf:clear-system name)
          (dependency-configure-registry)
          (check "central-registry-cleared" (null asdf:*central-registry*))
          (check "local-shadow-not-loaded" (null (asdf:find-system name nil))))))
    (format t "dependency-registry-checks selected=20 pass=~D~%" passed)
    (unless (= passed 20) (error "Incomplete registry regression selection"))))
