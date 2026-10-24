(in-package #:nshell.presentation)

(defun highlight-line-from-scanner
    (input scan-result cursor-position absolute-start)
  (declare (ignore input scan-result cursor-position absolute-start))
  (error 'nshell.application:wp-interface-not-implemented
         :owner-wp "E05"
         :interface 'highlight-line-from-scanner))
