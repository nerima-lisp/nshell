;;; Foundational, dependency-free string helpers shared across every layer.
(in-package #:nshell.util)

(defun string-prefix-p (prefix string)
  "True when STRING begins with PREFIX, compared case-sensitively."
  (and (<= (length prefix) (length string))
       (string= prefix string :end2 (length prefix))))

(defun utf-8-octets (text)
  "Encode TEXT as a freshly allocated vector of UTF-8 octets."
  (let ((octets (make-array (* 4 (length text))
                            :element-type '(unsigned-byte 8)))
        (count 0))
    (flet ((emit (octet)
             (setf (aref octets count) octet)
             (incf count)))
      (loop for character across text
            for code = (char-code character)
            do (cond
                 ((<= code #x7f)
                  (emit code))
                 ((<= code #x7ff)
                  (emit (logior #xc0 (ash code -6)))
                  (emit (logior #x80 (logand code #x3f))))
                 ((or (<= code #xd7ff)
                      (<= #xe000 code #xffff))
                  (emit (logior #xe0 (ash code -12)))
                  (emit (logior #x80 (logand (ash code -6) #x3f)))
                  (emit (logior #x80 (logand code #x3f))))
                 ((and (<= #x10000 code)
                       (<= code #x10ffff))
                  (emit (logior #xf0 (ash code -18)))
                  (emit (logior #x80 (logand (ash code -12) #x3f)))
                  (emit (logior #x80 (logand (ash code -6) #x3f)))
                  (emit (logior #x80 (logand code #x3f))))
                 (t
                  (error "Cannot encode character U+~8,'0X as UTF-8."
                         code)))))
    (subseq octets 0 count)))
