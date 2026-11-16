(in-package #:nshell.feature.machine)

;;; The full-output store of ux/U6: each session saves cut output under
;;; <root>/s_XXXXXX/, and only the newest sessions are kept. Every directory
;;; and file is created with owner-only permissions and checked without
;;; following symlinks; a check that fails yields NIL so the caller omits path.

(defun output-store-root ()
  "Return the store root as a native directory namestring ending in /:
$XDG_CACHE_HOME/nshell/out/ when XDG_CACHE_HOME is absolute, otherwise
~/.cache/nshell/out/."
  (let ((xdg (host-kit:getenv "XDG_CACHE_HOME")))
    (flet ((under (base suffix)
             (concatenate 'string (string-right-trim "/" base) "/" suffix)))
      (if (and xdg (plusp (length xdg)) (char= #\/ (char xdg 0)))
          (under xdg "nshell/out/")
          (under (sb-ext:native-namestring (user-homedir-pathname))
                 ".cache/nshell/out/")))))

(defstruct (output-session (:constructor %make-output-session (id directory)))
  "ID is the directory's basename; DIRECTORY is its namestring ending in /."
  id directory)

(defun %without-trailing-slash (path)
  (let ((trimmed (string-right-trim "/" path)))
    (if (zerop (length trimmed)) "/" trimmed)))

(defun %errno-p (condition &rest errnos)
  (member (sb-posix:syscall-errno condition) errnos))

(defun %ensure-directories (path)
  "Create the missing directories of PATH with mode 0700."
  (loop for slash = (position #\/ path :start 1)
          then (position #\/ path :start (1+ slash))
        for prefix = (if slash (subseq path 0 slash) path)
        do (handler-case (sb-posix:mkdir prefix #o700)
             (sb-posix:syscall-error (condition)
               (unless (%errno-p condition sb-posix:eexist)
                 (error condition))))
        while slash))

(defun %private-descriptor-refusal (fd type)
  "Return NIL when open descriptor FD is of file TYPE (an S_IF constant), is
owned by this user, and gives group and other no access; otherwise return a
phrase saying which of these fails."
  (let* ((stat (sb-posix:fstat fd))
         (mode (sb-posix:stat-mode stat)))
    (cond ((/= (logand mode sb-posix:s-ifmt) type)
           (if (= type sb-posix:s-ifdir) "is not a directory" "is not a regular file"))
          ((/= (sb-posix:stat-uid stat) (sb-posix:geteuid))
           "is not owned by this user")
          ((/= 0 (logand mode #o077))
           "is accessible by group or other"))))

(defun %private-directory-p (path)
  "Return true when PATH is a real directory owned by this user that group and
other cannot access. A symlink at PATH is refused, not followed. PATH's mode is
never changed: a directory with group or other bits is refused."
  (handler-case
      (let ((fd (sb-posix:open (%without-trailing-slash path)
                               (logior sb-posix:o-rdonly sb-posix:o-nofollow
                                       sb-posix:o-directory))))
        (unwind-protect
             (null (%private-descriptor-refusal fd sb-posix:s-ifdir))
          (sb-posix:close fd)))
    (sb-posix:syscall-error () nil)))

(defun open-output-session (&key (root (output-store-root)))
  "Create a private session directory under ROOT and return its OUTPUT-SESSION,
or NIL when ROOT or the new directory is not private to this user."
  (handler-case
      (let ((root (concatenate 'string (%without-trailing-slash root) "/")))
        (%ensure-directories (%without-trailing-slash root))
        (when (%private-directory-p root)
          (let ((directory (sb-posix:mkdtemp (concatenate 'string root "s_XXXXXX"))))
            (if (%private-directory-p directory)
                (%make-output-session (subseq directory (length root))
                                      (concatenate 'string directory "/"))
                (progn (ignore-errors (sb-posix:rmdir directory))
                       nil)))))
    (sb-posix:syscall-error () nil)))

(defun %plain-file-name-p (name)
  (and (stringp name)
       (plusp (length name))
       (not (find #\/ name))
       (not (find (code-char 0) name))
       (not (member name '("." "..") :test #'string=))))

(defun output-session-write (session name text)
  "Write TEXT as UTF-8 to a new file NAME in SESSION's directory with mode 0600
and return its path, or NIL when NAME is not a plain file name, the file
already exists, or the write fails."
  (unless (%plain-file-name-p name)
    (return-from output-session-write nil))
  (let ((path (concatenate 'string (output-session-directory session) name))
        (created nil))
    (handler-case
        (let ((fd (sb-posix:open path
                                 (logior sb-posix:o-wronly sb-posix:o-creat
                                         sb-posix:o-excl sb-posix:o-nofollow)
                                 #o600)))
          (setf created t)
          (let ((stream (handler-case
                            (progn
                              (sb-posix:fchmod fd #o600)
                              (sb-sys:make-fd-stream fd :output t
                                                        :element-type 'character
                                                        :external-format :utf-8
                                                        :auto-close t))
                          (error (condition)
                            (sb-posix:close fd)
                            (error condition)))))
            (with-open-stream (stream stream)
              (write-string text stream)
              (finish-output stream)))
          path)
      (error ()
        (when created
          (ignore-errors (sb-posix:unlink path)))
        nil))))

;;; Pruning

(defun %session-name-p (name)
  (and (= (length name) 8)
       (string= "s_" name :end2 2)
       (every (lambda (char) (and (char< char (code-char 128)) (alphanumericp char)))
              (subseq name 2))))

(defun %directory-entries (path)
  "Return the entry names of directory PATH other than . and .."
  (let ((dir (sb-posix:opendir path)))
    (unwind-protect
         (loop for entry = (sb-posix:readdir dir)
               until (sb-alien:null-alien entry)
               for name = (sb-posix:dirent-name entry)
               unless (member name '("." "..") :test #'string=)
                 collect name)
      (sb-posix:closedir dir))))

(defun %lstat-or-nil (path)
  (handler-case (sb-posix:lstat path)
    (sb-posix:syscall-error (condition)
      (if (%errno-p condition sb-posix:enoent) nil (error condition)))))

(defun %file-type (stat)
  (logand (sb-posix:stat-mode stat) sb-posix:s-ifmt))

(defun %ignoring-enoent (function &rest arguments)
  (handler-case (apply function arguments)
    (sb-posix:syscall-error (condition)
      (unless (%errno-p condition sb-posix:enoent)
        (error condition)))))

(defun %delete-session-directory (directory)
  "Unlink the non-directory entries of DIRECTORY, then remove it. Leave it in
place when it holds a subdirectory, which no session creates."
  (let* ((entries (handler-case (%directory-entries directory)
                    (sb-posix:syscall-error (condition)
                      (if (%errno-p condition sb-posix:enoent)
                          (return-from %delete-session-directory t)
                          (error condition)))))
         (paths (mapcar (lambda (name) (concatenate 'string directory "/" name))
                        entries)))
    (when (some (lambda (path)
                  (let ((stat (%lstat-or-nil path)))
                    (and stat (= (%file-type stat) sb-posix:s-ifdir))))
                paths)
      (return-from %delete-session-directory nil))
    (dolist (path paths)
      (%ignoring-enoent #'sb-posix:unlink path))
    (%ignoring-enoent #'sb-posix:rmdir directory)
    t))

(defun prune-output-sessions (&key (root (output-store-root)) (keep 50) except)
  "Delete this user's session directories under ROOT so that at most KEEP
remain, newest by mtime first. EXCEPT (an OUTPUT-SESSION) is never deleted and
counts as one of the KEEP. Return the deleted directories and,
as a second value, a list of (directory . condition) for those that could not
be deleted."
  (let ((root (%without-trailing-slash root))
        (except-directory (and except
                               (%without-trailing-slash
                                (output-session-directory except))))
        (uid (sb-posix:geteuid))
        (deleted '())
        (failed '()))
    (unless (handler-case
                (let ((stat (sb-posix:lstat root)))
                  (and (= (%file-type stat) sb-posix:s-ifdir)
                       (= (sb-posix:stat-uid stat) uid)))
              (sb-posix:syscall-error () nil))
      (return-from prune-output-sessions (values nil nil)))
    (let ((sessions
            (loop for name in (handler-case (%directory-entries root)
                                (sb-posix:syscall-error (condition)
                                  (if (%errno-p condition sb-posix:enoent)
                                      nil
                                      (error condition))))
                  for path = (concatenate 'string root "/" name)
                  for stat = (and (%session-name-p name) (%lstat-or-nil path))
                  when (and stat
                            (= (%file-type stat) sb-posix:s-ifdir)
                            (= (sb-posix:stat-uid stat) uid))
                    collect (cons path (sb-posix:stat-mtime stat)))))
      (setf sessions (sort sessions
                           (lambda (left right)
                             (or (> (cdr left) (cdr right))
                                 (and (= (cdr left) (cdr right))
                                      (string> (car left) (car right)))))))
      ;; EXCEPT counts toward KEEP, so at most KEEP sessions remain in total.
      (let* ((except-present-p (and except-directory
                                    (assoc except-directory sessions :test #'equal)))
             (others (remove except-directory sessions :key #'car :test #'equal))
             (keep-others (if except-present-p (max 0 (1- keep)) keep)))
        (dolist (session (nthcdr keep-others others))
          (let ((directory (car session)))
            (handler-case
                (if (%delete-session-directory directory)
                    (push directory deleted)
                    (push (cons directory :has-subdirectory) failed))
              (error (condition)
                (push (cons directory condition) failed)))))))
    (values (nreverse deleted) (nreverse failed))))
