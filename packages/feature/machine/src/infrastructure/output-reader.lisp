(in-package #:nshell.feature.machine)

;;; Reading a saved output back for read_output (ux/U6). The root, the session
;;; directory and the file are each opened without following a symlink, the
;;; latter two relative to the descriptor of the directory above, and each is
;;; checked on its own descriptor. No path is resolved again after its check,
;;; and the bytes come from the checked file descriptor.

(define-condition saved-output-error (error)
  ((reason :initarg :reason :reader saved-output-error-reason)
   (message :initarg :message :reader saved-output-error-message))
  (:documentation "REASON is :REQUEST when the request is malformed (an id or
name that is not one the store makes, an offset past the end or inside a
character, a limit out of range) and :STORE when the store refuses to serve
the file.")
  (:report (lambda (condition stream)
             (write-string (saved-output-error-message condition) stream))))

(defun %saved-output-fail (reason format-control &rest arguments)
  (error 'saved-output-error :reason reason
                             :message (apply #'format nil format-control arguments)))

(defun %openat (dirfd name flags)
  "Open NAME relative to the directory descriptor DIRFD and return the new
descriptor, or signal SB-POSIX:SYSCALL-ERROR."
  ;; sb-posix has no openat. It is variadic, but the mode argument is read only
  ;; with O_CREAT, so a call with the three fixed arguments is valid in every
  ;; ABI, Darwin's arm64 one (which passes variadic arguments on the stack)
  ;; included.
  (let ((fd (sb-alien:alien-funcall
             (sb-alien:extern-alien "openat"
                                    (function sb-alien:int sb-alien:int
                                              sb-alien:c-string sb-alien:int))
             dirfd name flags)))
    (if (minusp fd)
        (error 'sb-posix:syscall-error :errno (sb-alien:get-errno) :name "openat")
        fd)))

(defun %open-refusal (condition)
  (let ((errno (sb-posix:syscall-errno condition)))
    (cond ((= errno sb-posix:enoent) "does not exist")
          ((= errno sb-posix:eloop) "is a symlink")
          ;; Linux reports a symlink opened with O_DIRECTORY as ENOTDIR.
          ((= errno sb-posix:enotdir) "is a symlink or not a directory")
          (t (format nil "cannot be opened (~A)" (sb-int:strerror errno))))))

(defun %open-private (dirfd name flags type what)
  "Open NAME with FLAGS and O_NOFOLLOW, relative to DIRFD or, when DIRFD is
NIL, as a path, and return the descriptor once it is of TYPE, owned by this
user and closed to group and other. Otherwise signal a :STORE refusal that
names WHAT."
  (let* ((flags (logior flags sb-posix:o-nofollow))
         (fd (handler-case (if dirfd
                               (%openat dirfd name flags)
                               (sb-posix:open name flags))
               (sb-posix:syscall-error (condition)
                 (%saved-output-fail :store "~A ~A" what (%open-refusal condition)))))
         (checked nil))
    (unwind-protect
         (let ((refusal (%private-descriptor-refusal fd type)))
           (when refusal
             (%saved-output-fail :store "~A ~A" what refusal))
           (setf checked t)
           fd)
      (unless checked
        (sb-posix:close fd)))))

(defmacro %with-private-descriptor ((var dirfd name flags type what) &body body)
  `(let ((,var (%open-private ,dirfd ,name ,flags ,type ,what)))
     (unwind-protect (progn ,@body)
       (sb-posix:close ,var))))

(defun %utf-8-continuation-p (octet)
  (= #x80 (logand octet #xc0)))

(defun %read-into (fd buffer)
  "Fill BUFFER from FD's current position and return the octets read, fewer
only at the end of the file."
  (sb-sys:with-pinned-objects (buffer)
    (loop with sap = (sb-sys:vector-sap buffer)
          with total = 0
          while (< total (length buffer))
          do (let ((count (sb-posix:read fd (sb-sys:sap+ sap total)
                                         (- (length buffer) total))))
               (when (zerop count)
                 (loop-finish))
               (incf total count))
          finally (return total))))

(defun %read-chunk (fd offset limit)
  (let ((size (sb-posix:stat-size (sb-posix:fstat fd))))
    (when (> offset size)
      (%saved-output-fail :request "offset ~D is past the end of the output (~D bytes)"
                          offset size))
    ;; Three octets past LIMIT are enough to finish a character LIMIT cuts.
    (let* ((buffer (make-array (min (- size offset) (+ limit 3))
                               :element-type '(unsigned-byte 8)))
           (count (progn (sb-posix:lseek fd offset sb-posix:seek-set)
                         (%read-into fd buffer)))
           (end (min limit count)))
      (when (and (plusp count) (%utf-8-continuation-p (aref buffer 0)))
        (%saved-output-fail :request "offset ~D is inside a UTF-8 character" offset))
      (when (< end count)
        (loop while (and (plusp end) (%utf-8-continuation-p (aref buffer end)))
              do (decf end))
        ;; A character longer than LIMIT is returned whole, so a read progresses.
        (when (zerop end)
          (setf end 1)
          (loop while (and (< end count) (%utf-8-continuation-p (aref buffer end)))
                do (incf end))))
      (values (sb-ext:octets-to-string buffer :end end
                                              :external-format
                                              '(:utf-8 :replacement #\Replacement_Character))
              (+ offset end)
              size))))

(defun read-saved-output (id name &key (offset 0) (limit +default-max-output-bytes+)
                                       (root (output-store-root)))
  "Read file NAME of session ID under ROOT from byte OFFSET. Return the text of
at most LIMIT bytes, cut back to a character boundary but always at least one
character before the end; the offset after it; and the file's size in bytes.
Signal SAVED-OUTPUT-ERROR when the request is malformed or the store refuses
it: a part that is missing, a symlink, not this user's, open to group or
other, or of the wrong file type."
  (unless (and (stringp id) (%session-name-p id))
    (%saved-output-fail :request "id must be a session id: s_ and 6 ASCII letters or digits"))
  (unless (%plain-file-name-p name)
    (%saved-output-fail :request "the file name must be a plain name"))
  (unless (and (integerp offset) (>= offset 0))
    (%saved-output-fail :request "offset must be a non-negative integer"))
  (unless (and (integerp limit) (<= 1 limit +default-max-output-bytes+))
    (%saved-output-fail :request "limit must be an integer from 1 to ~D"
                        +default-max-output-bytes+))
  (let ((directory (logior sb-posix:o-rdonly sb-posix:o-directory)))
    (%with-private-descriptor (root-fd nil (%without-trailing-slash root) directory
                                       sb-posix:s-ifdir "the output store root")
      (%with-private-descriptor (session-fd root-fd id directory sb-posix:s-ifdir
                                            (format nil "session ~A" id))
        ;; O_NONBLOCK: opening a FIFO put in the file's place must not wait.
        (%with-private-descriptor (fd session-fd name
                                      (logior sb-posix:o-rdonly sb-posix:o-nonblock)
                                      sb-posix:s-ifreg
                                      (format nil "~A of session ~A" name id))
          (%read-chunk fd offset limit))))))
