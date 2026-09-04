(in-package #:nshell/test)

(defun octets->string (octets count)
  (coerce (loop for i below count
                collect (code-char (aref octets i)))
          'string))

(defun string->octets (string)
  (nshell.util:utf-8-octets string))

(defun line (text)
  (concatenate 'string text (string #\Newline)))

(defmacro with-open-pty ((master slave slave-name) &body body)
  "Bind a raw PTY pair and close both descriptors after BODY."
  `(multiple-value-bind (,master ,slave ,slave-name)
       (nshell.infrastructure.acl:open-pty)
     (unwind-protect
          (progn ,@body)
       (nshell.infrastructure.acl:pty-close ,master ,slave))))

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

  (it "pty-spawn-validates-input-contract-before-opening-a-pty"
    "PTY creation rejects malformed programs, arguments, and dimensions early."
    (expect (lambda ()
              (nshell.infrastructure.acl:pty-spawn 42 '()))
            :to-throw 'type-error)
    (expect (lambda ()
              (nshell.infrastructure.acl:pty-spawn "/bin/echo" '(42)))
            :to-throw 'error)
    (expect (lambda ()
              (nshell.infrastructure.acl:pty-spawn "/bin/echo" '() :rows 0))
            :to-throw 'error)
    (expect (lambda ()
              (nshell.infrastructure.acl:pty-spawn "/bin/echo" '() :cols -1))
            :to-throw 'error))

  (it "checked-syscall-macro-returns-result-after-body"
    "The syscall boundary macro keeps the result available after successful work."
    (let ((body-result nil))
      (flet ((nshell.infrastructure.acl::%syscall-failed-p (result)
               (declare (ignore result))
               nil))
        (expect 7 :to-equal
                (nshell.infrastructure.acl::with-checked-syscall
                    ("test-syscall" 7)
                  (setf body-result :ran))))
      (expect :ran :to-equal body-result)))

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

  (it "pty-child-argv-vectors-are-null-terminated"
    "Child exec vectors preserve argument order and terminate with a null pointer."
    #+(or darwin linux)
    (let ((vector (nshell.infrastructure.acl::%make-c-string-vector
                   '("program" "--flag" "value"))))
      (unwind-protect
           (progn
             (expect "program" :to-equal
                     (sb-alien:deref vector 0))
             (expect "--flag" :to-equal
                     (sb-alien:deref vector 1))
             (expect "value" :to-equal
                     (sb-alien:deref vector 2))
             (expect nil :to-be
                     (sb-alien:deref vector 3)))
        (nshell.infrastructure.acl::%free-c-string-vector vector)))
    #-(or darwin linux)
    (skip "PTY tests are only supported on Darwin and Linux"))

  (it "pty-exec-vector-scope-cleans-up-after-body"
    "The child exec vector scope exposes both vectors and always returns the body result."
    #+(or darwin linux)
    (expect :completed :to-equal
            (nshell.infrastructure.acl::%with-pty-exec-vectors
                (argv envp "program" '("--flag"))
              (expect "program" :to-equal (sb-alien:deref argv 0))
              (expect nil :to-be (sb-alien:deref argv 2))
              (expect (sb-alien:deref envp 0) :to-be-truthy)
              :completed))
    #-(or darwin linux)
    (skip "PTY tests are only supported on Darwin and Linux"))

  (it "pty-ready-pipe-transfers-status-byte"
    "The readiness protocol transfers exactly one setup status byte."
    #+(or darwin linux)
    (multiple-value-bind (read-fd write-fd) (sb-posix:pipe)
      (unwind-protect
           (progn
              (expect (nshell.infrastructure.acl::%pty-write-ready-byte
                       write-fd
                       nshell.infrastructure.acl::+pty-child-ready-ok+)
                      :to-be-truthy)
             (expect nshell.infrastructure.acl::+pty-child-ready-ok+ :to-equal
                     (nshell.infrastructure.acl::%pty-read-ready-byte read-fd)))
        (nshell.infrastructure.acl::%pty-close-fd read-fd)
        (nshell.infrastructure.acl::%pty-close-fd write-fd)))
    #-(or darwin linux)
    (skip "PTY tests are only supported on Darwin and Linux"))

  (it "pty-ready-pipe-reports-read-boundaries"
    "Readiness failures distinguish an invalid descriptor from EOF."
    #+(or darwin linux)
    (progn
      (expect (lambda ()
                (nshell.infrastructure.acl::%pty-read-ready-byte -1))
              :to-throw 'error)
      (multiple-value-bind (read-fd write-fd) (sb-posix:pipe)
        (unwind-protect
             (progn
               (nshell.infrastructure.acl::%pty-close-fd write-fd)
               (setf write-fd nil)
               (expect (lambda ()
                         (nshell.infrastructure.acl::%pty-read-ready-byte read-fd))
                       :to-throw 'error))
          (nshell.infrastructure.acl::%pty-close-fd read-fd)
          (nshell.infrastructure.acl::%pty-close-fd write-fd))))
    #-(or darwin linux)
    (skip "PTY tests are only supported on Darwin and Linux"))

  (it "pty-ready-pipe-reports-child-setup-failure"
    "The parent rejects a readiness byte that reports child setup failure."
    #+(or darwin linux)
    (multiple-value-bind (read-fd write-fd) (sb-posix:pipe)
      (unwind-protect
           (progn
             (expect (nshell.infrastructure.acl::%pty-write-ready-byte
                      write-fd
                      nshell.infrastructure.acl::+pty-child-ready-error+)
                     :to-be-truthy)
             (expect (lambda ()
                       (nshell.infrastructure.acl::%wait-for-pty-child-ready
                        read-fd
                        -1))
                     :to-throw 'error))
        (nshell.infrastructure.acl::%pty-close-fd read-fd)
        (nshell.infrastructure.acl::%pty-close-fd write-fd)))
    #-(or darwin linux)
    (skip "PTY tests are only supported on Darwin and Linux"))

  (it "pty-child-ready-signal-closes-invalid-descriptors"
    "The child readiness signal remains cleanup-safe after a write failure."
    #+(or darwin linux)
    (expect nil :to-be
            (nshell.infrastructure.acl::%signal-pty-child-ready -1 0))
    #-(or darwin linux)
    (skip "PTY tests are only supported on Darwin and Linux"))

  (it "pty-window-size-reports-invalid-descriptors"
    "Window-size setup surfaces ioctl failures to the caller."
    #+(or darwin linux)
    (expect (lambda ()
              (nshell.infrastructure.acl::%set-pty-window-size -1 24 80))
            :to-throw 'error)
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

  (it "pty-io-reports-invalid-descriptor-errors"
    "Read and write failures remain visible at the PTY boundary."
    #+(or darwin linux)
    (let ((buffer (make-array 8 :element-type '(unsigned-byte 8))))
      (expect (lambda ()
                (nshell.infrastructure.acl:pty-read -1 buffer 8))
              :to-throw 'error)
      (expect (lambda ()
                (nshell.infrastructure.acl:pty-write
                 -1
                 (make-array 1 :element-type '(unsigned-byte 8)
                               :initial-element 0)))
              :to-throw 'error))
    #-(or darwin linux)
    (skip "PTY tests are only supported on Darwin and Linux"))

  (it "pty-open-write-read-close"
    "PTY can be opened, used in both directions, and closed."
    #-(or darwin linux)
    (skip "PTY tests are only supported on Darwin and Linux")
    #+(or darwin linux)
    (skip-when-pty-round-trip-unreliable "PTY master/slave round-trip I/O is unreliable"
    (with-open-pty (master slave slave-name)
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
          (expect (search "slave-to-master" (octets->string from-slave count)) :to-be-truthy)))))

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

  (it "with-pty-allows-omitting-slave-name"
    "WITH-PTY does not require callers to bind the diagnostic slave name."
    #-(or darwin linux)
    (skip "PTY tests are only supported on Darwin and Linux")
    #+(or darwin linux)
    (skip-when-pty-unavailable "requires a usable PTY"
      (nshell.infrastructure.acl:with-pty (master slave)
        (expect (streamp master) :to-be-truthy)
        (expect (streamp slave) :to-be-truthy)))))

(describe "pty-cleanup-tests"
  (it "with-pty-closes-streams-when-body-signals"
    "WITH-PTY closes both streams before propagating a body error."
    #-(or darwin linux)
    (skip "PTY tests are only supported on Darwin and Linux")
    #+(or darwin linux)
    (skip-when-pty-unavailable "requires a usable PTY"
      (let ((master-stream nil)
            (slave-stream nil))
        (expect (lambda ()
                  (nshell.infrastructure.acl:with-pty (master slave)
                    (setf master-stream master
                          slave-stream slave)
                    (error "body failure")))
                :to-throw 'error)
        (expect (open-stream-p master-stream) :to-be-falsy)
        (expect (open-stream-p slave-stream) :to-be-falsy)))))
