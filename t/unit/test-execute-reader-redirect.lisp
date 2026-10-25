(in-package #:nshell/test)

(describe "execute-reader-redirect-source-tests"
  (it "opens-file-redirects-in-the-requested-mode-and-avoids-destination-fds"
    (with-temporary-function
        ((quote nshell.application:argv-scalar-string)
         (lambda (value &key source-span)
           (declare (ignore source-span))
           (check-type value string)
           value))
      (host-kit:with-temporary-directory (directory)
        (let* ((path (merge-pathnames "reader-redirect.txt" directory))
               (path-string (namestring path))
               (context (make-test-shell-context))
               (evaluated-target
                 (nshell.domain.parsing:make-evaluated-command-arg
                  path-string (list 0 1))))
          (flet ((write-source (fd text)
                   (let ((octets
                           (sb-ext:string-to-octets text :external-format :utf-8)))
                     (expect (length octets) :to-equal
                             (sb-sys:with-pinned-objects (octets)
                               (sb-posix:write fd
                                               (sb-sys:vector-sap octets)
                                               (length octets))))))
            (dolist (redirect-case
                      (list
                       (list :output-file 1 :output "new" "new")
                       (list :force-output-file 1 :output "new" "new")
                       (list :error-file 2 :output "new" "new")
                       (list :both-output-files nil :output "new" "new")
                       (list :append-output-file 1 :append "-tail" "old-tail")
                       (list :append-error-file 2 :append "-tail" "old-tail")
                       (list :append-both-output-files nil :append "-tail" "old-tail")))
              (destructuring-bind (kind descriptor mode text expected)
                  redirect-case
                (host-kit:write-file-string "old" path)
                (let* ((redirect
                         (nshell.domain.parsing:make-ast-redirect-entry
                          kind descriptor
                          (nshell.domain.parsing:make-command-arg path-string)
                          (list 0 1) 0))
                       (source-fd
                         (nshell.application::%open-reader-redirect-source
                          context redirect evaluated-target
                          :avoid-descriptors (list 0 1 2 3))))
                  (unwind-protect
                       (progn
                         (expect t :to-be (>= source-fd 4))
                         (expect nil :to-be
                                 (member source-fd (list 0 1 2 3) :test #'eql))
                         (write-source source-fd text))
                    (sb-posix:close source-fd))
                  (expect expected :to-equal
                          (host-kit:read-file-string path)))))))))))

  (it "opens-input-files-and-here-strings-as-parent-owned-readable-fds"
    (with-temporary-function
        ((quote nshell.application:argv-scalar-string)
         (lambda (value &key source-span)
           (declare (ignore source-span))
           (check-type value string)
           value))
      (host-kit:with-temporary-directory (directory)
        (let* ((path (merge-pathnames "reader-input.txt" directory))
               (path-string (namestring path))
               (context (make-test-shell-context)))
          (flet ((read-source (fd)
                   (let ((octets (make-array 128 :element-type '(unsigned-byte 8))))
                     (let ((count (sb-sys:with-pinned-objects (octets)
                                    (sb-posix:read fd
                                                   (sb-sys:vector-sap octets)
                                                   (length octets)))))
                       (sb-ext:octets-to-string
                        (subseq octets 0 count) :external-format :utf-8))))
            (host-kit:write-file-string (format nil "input~%") path)
            (let* ((redirect
                     (nshell.domain.parsing:make-ast-redirect-entry
                      :input-file 0
                      (nshell.domain.parsing:make-command-arg path-string)
                      (list 0 1) 0))
                   (evaluated-target
                     (nshell.domain.parsing:make-evaluated-command-arg
                      path-string (list 0 1)))
                   (source-fd
                     (nshell.application::%open-reader-redirect-source
                      context redirect evaluated-target
                      :avoid-descriptors (list 0 3))))
              (unwind-protect
                   (progn
                     (expect nil :to-be
                             (member source-fd (list 0 3) :test #'eql))
                     (expect (format nil "input~%") :to-equal
                             (read-source source-fd)))
                (sb-posix:close source-fd)))
            (let* ((redirect
                     (nshell.domain.parsing:make-ast-redirect-entry
                      :here-string 0
                      (nshell.domain.parsing:make-command-arg "unused")
                      (list 0 1) 1))
                   (evaluated-target
                     (nshell.domain.parsing:make-evaluated-command-arg
                      "here" (list 2 6)))
                   (source-fd
                     (nshell.application::%open-reader-redirect-source
                      context redirect evaluated-target
                      :avoid-descriptors (list 0 3))))
              (unwind-protect
                   (expect (format nil "here~%") :to-equal
                           (read-source source-fd))
                (sb-posix:close source-fd)))))))))

  (it "strips-tabs-before-expansion-and-preserves-quoted-heredoc-text"
    (let* ((environment
             (nshell.domain.environment:env-set
              (nshell.domain.environment:make-default-environment)
              "NAME" "value" nil))
           (context (make-test-shell-context :environment environment)))
      (flet ((read-source (fd)
               (let ((octets (make-array 128 :element-type '(unsigned-byte 8))))
                 (let ((count (sb-sys:with-pinned-objects (octets)
                                 (sb-posix:read fd
                                                (sb-sys:vector-sap octets)
                                                (length octets)))))
                   (sb-ext:octets-to-string
                    (subseq octets 0 count) :external-format :utf-8)))))
        (let* ((target
                 (nshell.domain.parsing:make-redirect-heredoc-target
                  (nshell.domain.parsing:make-command-arg "END")
                  (format nil "~C$NAME~%~Cplain~%" #\Tab #\Tab)
                  t t '(0 8)))
               (redirect
                 (nshell.domain.parsing:make-ast-redirect-entry
                  :here-document-strip-tabs 0 target '(0 8) 0))
               (source-fd
                 (nshell.application::%open-reader-redirect-source
                  context redirect nil :avoid-descriptors '(0 3))))
          (unwind-protect
               (expect (format nil "value~%plain~%") :to-equal
                       (read-source source-fd))
            (sb-posix:close source-fd)))
        (let* ((target
                 (nshell.domain.parsing:make-redirect-heredoc-target
                  (nshell.domain.parsing:make-command-arg "END" :single t)
                  (format nil "$NAME~%") nil nil '(0 6)))
               (redirect
                 (nshell.domain.parsing:make-ast-redirect-entry
                  :here-document 0 target '(0 6) 1))
               (source-fd
                 (nshell.application::%open-reader-redirect-source
                  context redirect nil :avoid-descriptors '(0 3))))
          (unwind-protect
               (expect (format nil "$NAME~%") :to-equal
                       (read-source source-fd))
            (sb-posix:close source-fd)))))))
