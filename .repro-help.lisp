(require :asdf)
(load
 (merge-pathnames
  #P"scripts/asdf-runtime.lisp"
  (uiop:pathname-directory-pathname
   (or *load-truename* *load-pathname*))))
(nshell-configure-writable-asdf-output)
(let* ((root (truename #P"./"))
       (parent (uiop:pathname-parent-directory-pathname root)))
  (asdf:initialize-source-registry
   (if (uiop:getenv "CL_SOURCE_REGISTRY")
     `(:source-registry (:directory ,root) :inherit-configuration)
     `(:source-registry (:directory ,root) (:tree ,parent) :inherit-configuration))))
(asdf:load-system :nshell)
(let ((sb-ext:*posix-argv* (list "nshell" "--help")))
  (funcall (symbol-function (find-symbol "MAIN" "NSHELL"))))
