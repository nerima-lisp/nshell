(in-package #:nshell/test)

(defun octets->string (octets count)
  (coerce (loop for i below count
                collect (code-char (aref octets i)))
          'string))

(defun string->octets (string)
  (nshell.util:utf-8-octets string))

(defun line (text)
  (concatenate 'string text (string #\Newline)))

(describe "pty-tests"
  (it "pty-data-boundaries-preserve-octets-and-close-empty-pair"
    "PTY data conversion and nil-safe cleanup preserve their contracts."
    (let ((octets (nshell.util:utf-8-octets "A~")))
      (expect '(65 126) :to-equal (coerce octets 'list)))
    (expect '(227 129 130 227 129 132)
            :to-equal
            (coerce (nshell.util:utf-8-octets "あい") 'list))
    (expect t :to-equal
            (nshell.infrastructure.acl:pty-close nil nil))
    #+(or darwin linux)
    (let ((flags (nshell.infrastructure.acl::%pty-open-flags)))
      (expect sb-posix:o-rdwr :to-equal
              (logand flags sb-posix:o-rdwr))
      (expect sb-posix:o-noctty :to-equal
              (logand flags sb-posix:o-noctty))))

  (it "pty-syscall-contract-distinguishes-success-and-failure"
    "Low-level syscall results use NIL or negative integers as failures."
    (expect (nshell.infrastructure.acl::%syscall-failed-p 0) :to-be-falsy)
    (expect (nshell.infrastructure.acl::%syscall-failed-p nil) :to-be-truthy)
    (expect (nshell.infrastructure.acl::%syscall-failed-p -1) :to-be-truthy)
    (expect 0 :to-equal
            (nshell.infrastructure.acl::%check-errno 0 "successful syscall"))
    (expect (lambda ()
            (nshell.infrastructure.acl::%check-errno nil "failed syscall"))
            :to-throw 'error))

  (it "pty-child-resource-helpers-are-nil-safe"
    "Child-side cleanup helpers tolerate absent or already-invalid resources."
    #+(or darwin linux)
    (progn
      (expect sb-posix:o-rdwr :to-equal
              (nshell.infrastructure.acl::%pty-child-open-flags))
      (expect nil :to-be
              (nshell.infrastructure.acl::%pty-close-fd nil))
      (expect nil :to-be
              (nshell.infrastructure.acl::%pty-close-fd -1))
      (expect nil :to-be
              (nshell.infrastructure.acl::%free-c-string-vector nil))
      (expect nil :to-be
              (nshell.infrastructure.acl::%signal-pty-child-ready nil 0)))
    #-(or darwin linux)
    (skip "PTY tests are only supported on Darwin and Linux"))

  (it "utf8-octets-preserves-code-point-boundaries"
    "The shared encoder emits the shortest valid UTF-8 form at every boundary."
    (flet ((encoded (code-point)
             (coerce (nshell.util:utf-8-octets
                      (string (code-char code-point)))
                     'list)))
      (expect '(127) :to-equal (encoded #x7f))
      (expect '(194 128) :to-equal (encoded #x80))
      (expect '(223 191) :to-equal (encoded #x7ff))
      (expect '(224 160 128) :to-equal (encoded #x800))
      (expect '() :to-equal
              (coerce (nshell.util:utf-8-octets "") 'list))))

  (it "pty-open-write-read-close"
    "PTY can be opened, used in both directions, and closed."
    #-(or darwin linux)
    (skip "PTY tests are only supported on Darwin and Linux")
    #+(or darwin linux)
    (skip-when-pty-round-trip-unreliable "PTY master/slave round-trip I/O is unreliable"
    (multiple-value-bind (master slave slave-name) (nshell.infrastructure.acl:open-pty)
      (unwind-protect
           (progn
             (expect (integerp master) :to-be-truthy)
             (expect (integerp slave) :to-be-truthy)
             (expect (stringp slave-name) :to-be-truthy)
             (let ((from-master (make-array 64 :element-type '(unsigned-byte 8))))
               (expect (length (line "master-to-slave")) :to-equal
                       (nshell.infrastructure.acl:pty-write master (line "master-to-slave")))
               (let ((count (nshell.infrastructure.acl:pty-read slave from-master 64)))
                 (expect (plusp count) :to-be-truthy)
                 (expect (search "master-to-slave" (octets->string from-master count)) :to-be-truthy)))
             (let ((from-slave (make-array 64 :element-type '(unsigned-byte 8))))
               (nshell.infrastructure.acl:pty-write slave (string->octets (line "slave-to-master")))
               (let ((count (nshell.infrastructure.acl:pty-read master from-slave 64)))
                 (expect (plusp count) :to-be-truthy)
                 (expect (search "slave-to-master" (octets->string from-slave count)) :to-be-truthy))))
        (nshell.infrastructure.acl:pty-close master slave)))))

  (it "pty-close-is-idempotent-for-shared-descriptor"
    "PTY cleanup does not close a descriptor twice when both slots share it."
    #-(or darwin linux)
    (skip "PTY tests are only supported on Darwin and Linux")
    #+(or darwin linux)
    (multiple-value-bind (master slave) (nshell.infrastructure.acl:open-pty)
      (unwind-protect
           (expect t :to-equal
                   (nshell.infrastructure.acl:pty-close master master))
        (nshell.infrastructure.acl:pty-close nil slave))))

  (it "with-pty-binds-streams"
    "WITH-PTY binds usable unbuffered streams."
    #-(or darwin linux)
    (skip "PTY tests are only supported on Darwin and Linux")
    #+(or darwin linux)
    (skip-when-pty-unavailable "requires a usable PTY"
      (nshell.infrastructure.acl:with-pty (master slave slave-name)
        (expect (streamp master) :to-be-truthy)
        (expect (streamp slave) :to-be-truthy)
        (expect (stringp slave-name) :to-be-truthy)))))
