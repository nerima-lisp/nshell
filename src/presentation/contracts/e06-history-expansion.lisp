(in-package #:nshell.presentation)

(defun expand-history-input (raw-source)
  (declare (ignore raw-source))
  (error (quote nshell.application:wp-interface-not-implemented)
         :owner-wp "E06"
         :interface (quote expand-history-input)))

(defun source-span-to-origin-span (source-map expanded-span)
  (declare (ignore source-map expanded-span))
  (error (quote nshell.application:wp-interface-not-implemented)
         :owner-wp "E06"
         :interface (quote source-span-to-origin-span)))
