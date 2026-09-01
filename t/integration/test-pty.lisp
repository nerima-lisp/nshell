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
