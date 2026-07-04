(in-package #:nshell.application)

(defun %format-function-definition (name body-lines)
  (with-output-to-string (out)
    (format out "function ~a~%" name)
    (dolist (line body-lines)
      (format out "  ~a~%" line))
    (format out "end~%")))

(defun %store-function-body (context name args)
  (let ((body-line (%string-join
                    (if (and (rest args)
                             (string= (car (last args)) "end"))
                        (butlast (rest args))
                        (rest args))
                    " ")))
    (%store-shell-function-definition context
                                      name
                                      (if (string= body-line "")
                                          nil
                                          (list body-line))
                                      nil)
    (values nil 0)))

(defun %format-functions (table &optional names)
  (%format-name-table
   table
   (lambda (out name body-lines)
     (write-string (%format-function-definition name body-lines) out))
   names))

(defun %builtin-function (context args)
  (let ((table (shell-context-function-table context)))
    (%table-builtin-case args
      (:empty
       (values (%format-functions table) 0))
      (:option ("-e" "--erase")
       (%with-required-argument (%builtin-function args "function" "-e" "a name" 2)
         (%table-erase-names
          table
          (rest args)
          :on-erase (lambda (name)
                      (remhash name (shell-context-function-source-table context))))))
      (:option ("-q" "--query")
       (values nil (%table-query-status table (rest args))))
      (:default
       (if (rest args)
           (%store-function-body context (first args) args)
           (values (%format-functions table args)
                   (%table-query-status table (list (first args)))))))))
