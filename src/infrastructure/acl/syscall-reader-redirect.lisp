(in-package #:nshell.infrastructure.acl)

(defun %reader-redirect-source-fd (fd avoid-descriptors)
  (let* ((minimum (1+ (reduce #'max avoid-descriptors :initial-value 2)))
         (relocate-p (or (< fd 3) (member fd avoid-descriptors :test #'eql))))
    (if relocate-p
        (let ((duplicate nil)
              (keep-duplicate-p nil))
          (unwind-protect
              (progn
                (setf duplicate (sb-posix:fcntl fd +spawn-f-dupfd+ minimum))
                (%spawn-set-close-on-exec duplicate)
                (sb-posix:close fd)
                (setf keep-duplicate-p t)
                duplicate)
            (unless keep-duplicate-p
              (when duplicate
                (ignore-errors (sb-posix:close duplicate))))))
      (progn
        (%spawn-set-close-on-exec fd)
        fd))))

(defun open-reader-redirect-file (path mode &key avoid-descriptors)
  "Open PATH for a reader redirect and return its parent-owned source fd.
MODE is :INPUT, :OUTPUT, or :APPEND."
  (let* ((path
          (if (pathnamep path)
              (namestring path)
              path))
         (flags
          (logior
           (ecase mode
             (:input sb-posix:o-rdonly)
             (:output
              (logior sb-posix:o-wronly sb-posix:o-creat sb-posix:o-trunc))
             (:append
              (logior sb-posix:o-wronly sb-posix:o-creat sb-posix:o-append)))
           #+linux +spawn-linux-o-cloexec+
           #+darwin +spawn-darwin-o-cloexec+))
         (fd
          (if (eq mode :input)
              (sb-posix:open path flags)
              (sb-posix:open path flags #o666)))
         (complete-p nil))
    (unwind-protect
        (prog1
          (%reader-redirect-source-fd fd avoid-descriptors)
          (setf complete-p t))
      (unless complete-p
        (ignore-errors (sb-posix:close fd))))))

(defun open-reader-redirect-data (contents &key avoid-descriptors)
  "Materialize CONTENTS in an unlinked file and return its parent-owned source fd."
  (check-type contents string)
  (let ((template
         (namestring
          (merge-pathnames "nshell-reader-redirect-XXXXXX"
                           (uiop:temporary-directory))))
        (fd nil)
        (temporary-path nil)
        (complete-p nil))
    (unwind-protect
        (multiple-value-bind (opened-fd opened-path) (sb-posix:mkstemp template)
          (setf fd opened-fd
                temporary-path opened-path)
          (unwind-protect
              (progn
                (%spawn-set-close-on-exec fd)
                (sb-posix:unlink temporary-path)
                (setf temporary-path nil)
                (let ((octets
                       (sb-ext:string-to-octets contents
                                                :external-format
                                                :utf-8)))
                  (loop with offset = 0
                        while (< offset (length octets))
                        do (let* ((remaining (subseq octets offset))
                                  (written
                                   (sb-sys:with-pinned-objects (remaining)
                                                               (sb-posix:write
                                                                fd
                                                                (sb-sys:vector-sap
                                                                 remaining)
                                                                (length
                                                                 remaining)))))
                             (unless (plusp written)
                               (error
                                "Could not finish writing reader redirect data"))
                             (incf offset written))))
                (sb-posix:lseek fd 0 sb-posix:seek-set)
                (setf fd (%reader-redirect-source-fd fd avoid-descriptors))
                (prog1
                  fd
                  (setf complete-p t)))
            (when temporary-path
              (ignore-errors (sb-posix:unlink temporary-path)))))
      (unless complete-p
        (when fd
          (ignore-errors (sb-posix:close fd))))
      (when temporary-path
        (ignore-errors (sb-posix:unlink temporary-path))))))
