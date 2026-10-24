(in-package #:nshell.domain.completion)

(defun completion-context-for-scan (scan-result cursor)
  (declare (ignore scan-result cursor))
  (error 'nshell.application:wp-interface-not-implemented
         :owner-wp "C06"
         :interface 'completion-context-for-scan))

(defun complete-in-context
    (kb partial-input context &key path filesystem alias-table function-table
                                    variable-names directory home-directory)
  (declare
   (ignore kb partial-input context path filesystem alias-table function-table
           variable-names directory home-directory))
  (error 'nshell.application:wp-interface-not-implemented
         :owner-wp "C06"
         :interface 'complete-in-context))
