(in-package #:nshell.domain.parsing)

(defun redirects-require-shell-wrapper-p (redirects)
  "Return true when REDIRECTS contain descriptor duplication.

Descriptor duplication must be applied to the child's actual file descriptors;
sharing the parent-side Lisp streams cannot reproduce source-ordered `n>&m`
semantics.  The shell wrapper performs that operation before `exec`."
  (some (lambda (entry)
          (eq (car entry) :fd-dup))
        redirects))

(defun %shell-quote (value)
  (with-output-to-string (stream)
    (write-char #\' stream)
    (loop for character across (princ-to-string value)
          do (if (char= character #\')
                 (write-string "'\\''" stream)
                 (write-char character stream)))
    (write-char #\' stream)))

(defun %shell-heredoc-delimiter (body index)
  (let ((delimiter (format nil "NSHELL_HEREDOC_~d" index)))
    (loop while (and body (search delimiter body :test #'char=))
          do (incf index)
             (setf delimiter (format nil "NSHELL_HEREDOC_~d" index)))
    delimiter))

(defun shell-redirect-script (redirects)
  "Render REDIRECTS as source-ordered shell redirections for a child wrapper."
  (with-output-to-string (stream)
    (write-string "exec \"$@\"" stream)
    (let ((heredocs '())
          (index 0))
      (dolist (entry redirects)
        (let ((kind (car entry))
              (target (cdr entry)))
          (case kind
            ((:> :>> :2> :2>> :<)
             (format stream " ~a~a"
                     (case kind
                       (:> ">") (:>> ">>") (:2> "2>")
                       (:2>> "2>>") (:< "<"))
                     (%shell-quote target)))
            (:&>
             (format stream " >~a 2>&1" (%shell-quote target)))
            (:&>>
             (format stream " >>~a 2>&1" (%shell-quote target)))
            (:2>&1
             (write-string " 2>&1" stream))
            (:<<<
             (let* ((body (format nil "~a~%" (or target "")))
                    (delimiter (%shell-heredoc-delimiter body index)))
               (incf index)
               (push (cons delimiter body) heredocs)
               (format stream " <<~a" (%shell-quote delimiter))))
            ((:<< :<<-)
             (let ((delimiter (%shell-heredoc-delimiter target index)))
               (incf index)
               (push (cons delimiter target) heredocs)
               (format stream " ~a~a"
                       (if (eq kind :<<-) "<<-" "<<")
                       (%shell-quote delimiter))))
            (:fd-dup
             (let* ((dup-target target)
                    (operator
                      (if (eq (redirect-fd-dup-target-operator dup-target)
                              :input)
                          "<&"
                          ">&"))
                    (source (redirect-fd-dup-target-source dup-target))
                    (destination (redirect-fd-dup-target-target dup-target)))
               (format stream " ~d~a~a"
                       source operator
                       (if (eq destination :close)
                           "-"
                           destination))))
            (otherwise
             (error "Unsupported shell redirect kind ~s" kind)))))
      (write-char #\Newline stream)
      (dolist (heredoc (nreverse heredocs))
        (let ((body (cdr heredoc)))
          (when body
            (write-string body stream)
            (unless (and (> (length body) 0)
                         (char= (char body (1- (length body))) #\Newline))
              (write-char #\Newline stream))))
        (format stream "~a~%" (car heredoc))))))
