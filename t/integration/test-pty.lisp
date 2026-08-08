(in-package #:nshell/test)

(defun octets->string (octets count)
  (coerce (loop for i below count
                collect (code-char (aref octets i)))
          'string))

(defun string->octets (string)
  (let ((octets (make-array (length string) :element-type '(unsigned-byte 8))))
    (loop for i below (length string)
          do (setf (aref octets i) (char-code (char string i))))
    octets))

(defun line (text)
  (concatenate 'string text (string #\Newline)))

(describe "pty-tests"
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
               (nshell.infrastructure.acl:pty-write master (string->octets (line "master-to-slave")))
               (let ((count (nshell.infrastructure.acl:pty-read slave from-master 64)))
                 (expect (plusp count) :to-be-truthy)
                 (expect (search "master-to-slave" (octets->string from-master count)) :to-be-truthy)))
             (let ((from-slave (make-array 64 :element-type '(unsigned-byte 8))))
               (nshell.infrastructure.acl:pty-write slave (string->octets (line "slave-to-master")))
               (let ((count (nshell.infrastructure.acl:pty-read master from-slave 64)))
                 (expect (plusp count) :to-be-truthy)
                 (expect (search "slave-to-master" (octets->string from-slave count)) :to-be-truthy))))
        (nshell.infrastructure.acl:pty-close master slave)))))

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
