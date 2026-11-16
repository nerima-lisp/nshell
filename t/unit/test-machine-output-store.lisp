(in-package #:nshell/test)

;;; The full-output store of ux/U6: private session directories under a root,
;;; exclusive owner-only files, and pruning to the newest sessions. Every test
;;; works in a temporary directory, never the real cache.

(defmacro with-machine-store-root ((root) &body body)
  "Bind ROOT to the namestring of <fresh temporary directory>/out/, which does
not exist yet."
  (let ((directory (gensym "DIRECTORY")))
    `(host-kit:with-temporary-directory (,directory)
       (let ((,root (concatenate 'string
                                 (string-right-trim
                                  "/" (sb-ext:native-namestring ,directory))
                                 "/out/")))
         ,@body))))

(defun machine-store-mode (path)
  (logand (sb-posix:stat-mode (sb-posix:lstat (string-right-trim "/" path))) #o7777))

(defun machine-store-exists-p (path)
  (handler-case (progn (sb-posix:lstat (string-right-trim "/" path)) t)
    (sb-posix:syscall-error () nil)))

(defun machine-store-make-session (root name mtime)
  (let ((path (concatenate 'string root name)))
    (sb-posix:mkdir path #o700)
    (with-open-file (out (concatenate 'string path "/1.txt") :direction :output)
      (write-string "x" out))
    (sb-posix:utimes path mtime mtime)
    path))

(defun machine-store-session-name (index)
  (format nil "s_t~5,'0D" index))

(describe "machine output store"
  (it "puts the root under an absolute XDG_CACHE_HOME, else under HOME"
    (let ((saved (host-kit:getenv "XDG_CACHE_HOME")))
      (unwind-protect
           (progn
             (sb-posix:setenv "XDG_CACHE_HOME" "/xdg/cache/" 1)
             (expect (nshell.feature.machine:output-store-root)
                     :to-equal "/xdg/cache/nshell/out/")
             (sb-posix:setenv "XDG_CACHE_HOME" "relative/cache" 1)
             (expect (nshell.feature.machine:output-store-root)
                     :to-equal (concatenate
                                'string
                                (string-right-trim
                                 "/" (sb-ext:native-namestring (user-homedir-pathname)))
                                "/.cache/nshell/out/")))
        (if saved
            (sb-posix:setenv "XDG_CACHE_HOME" saved 1)
            (sb-posix:unsetenv "XDG_CACHE_HOME")))))

  (it "creates a private session directory and exclusive private files"
    (with-machine-store-root (root)
      (let ((session (nshell.feature.machine:open-output-session :root root)))
        (expect session :to-be-truthy)
        (let ((id (nshell.feature.machine:output-session-id session))
              (directory (nshell.feature.machine:output-session-directory session)))
          (expect (length id) :to-be 8)
          (expect (subseq id 0 2) :to-equal "s_")
          (expect directory :to-equal (concatenate 'string root id "/"))
          (expect (machine-store-mode root) :to-be #o700)
          (expect (machine-store-mode directory) :to-be #o700)
          (let ((path (nshell.feature.machine:output-session-write
                       session "1.txt" (format nil "caf~C~%" (code-char #xe9)))))
            (expect path :to-equal (concatenate 'string directory "1.txt"))
            (expect (machine-store-mode path) :to-be #o600)
            (expect (uiop:read-file-string path :external-format :utf-8)
                    :to-equal (format nil "caf~C~%" (code-char #xe9))))
          (expect (nshell.feature.machine:output-session-write session "1.txt" "again")
                  :to-be-null)
          (expect (nshell.feature.machine:output-session-write session "../x" "x")
                  :to-be-null)
          (expect (machine-store-exists-p (concatenate 'string root "x"))
                  :to-be-null)))))

  (it "returns NIL for a symlinked root"
    (with-machine-store-root (root)
      (let ((target (concatenate 'string (string-right-trim "/" root) "-target")))
        (sb-posix:mkdir target #o700)
        (sb-posix:symlink target (string-right-trim "/" root))
        (expect (nshell.feature.machine:open-output-session :root root) :to-be-null)
        (expect (nshell.feature.machine::%directory-entries target) :to-be-null))))

  (it "does not write through a symlink planted at the file name"
    (with-machine-store-root (root)
      (let* ((session (nshell.feature.machine:open-output-session :root root))
             (directory (nshell.feature.machine:output-session-directory session))
             (victim (concatenate 'string root "victim")))
        (sb-posix:symlink victim (concatenate 'string directory "2.txt"))
        (expect (nshell.feature.machine:output-session-write session "2.txt" "x")
                :to-be-null)
        (expect (machine-store-exists-p victim) :to-be-null))))

  (it "prunes to the 50 newest sessions and never the excepted one"
    (with-machine-store-root (root)
      (let* ((current (nshell.feature.machine:open-output-session :root root))
             (current-directory
               (string-right-trim
                "/" (nshell.feature.machine:output-session-directory current)))
             (paths (loop for index from 0 below 60
                          collect (machine-store-make-session
                                   root (machine-store-session-name index)
                                   (+ 1000000 index)))))
        (sb-posix:utimes current-directory 1 1)
        (let ((deleted (nshell.feature.machine:prune-output-sessions
                        :root root :except current)))
          (expect (length deleted) :to-be 10)
          (expect (sort (copy-list deleted) #'string<)
                  :to-equal (subseq paths 0 10))
          (expect (count-if #'machine-store-exists-p paths) :to-be 50)
          (expect (every #'machine-store-exists-p (subseq paths 10)) :to-be-truthy)
          (expect (machine-store-exists-p current-directory) :to-be-truthy)))))

  (it "leaves other names, symlinks and directories with subdirectories alone"
    (with-machine-store-root (root)
      (sb-posix:mkdir (string-right-trim "/" root) #o700)
      (let* ((outside (concatenate 'string (string-right-trim "/" root) "-outside"))
             (other (machine-store-make-session root "keep-me" 1))
             (long-name (machine-store-make-session root "s_abcdefg" 1))
             (nested (machine-store-make-session root "s_nest00" 2))
             (link (concatenate 'string root "s_link00")))
        (sb-posix:mkdir outside #o700)
        (with-open-file (out (concatenate 'string outside "/keep.txt") :direction :output)
          (write-string "x" out))
        (sb-posix:symlink outside link)
        (sb-posix:mkdir (concatenate 'string nested "/sub") #o700)
        (multiple-value-bind (deleted failed)
            (nshell.feature.machine:prune-output-sessions :root root :keep 0)
          (expect deleted :to-be-null)
          (expect (mapcar #'car failed) :to-equal (list nested)))
        (expect (every #'machine-store-exists-p
                       (list other long-name nested link
                             (concatenate 'string outside "/keep.txt")))
                :to-be-truthy))))

  (it "tolerates a session directory that vanishes during pruning"
    (with-machine-store-root (root)
      (sb-posix:mkdir (string-right-trim "/" root) #o700)
      (let ((path (machine-store-make-session root "s_gone00" 1)))
        (expect (nshell.feature.machine::%delete-session-directory path) :to-be-truthy)
        (expect (machine-store-exists-p path) :to-be-null)
        (expect (nshell.feature.machine::%delete-session-directory path)
                :to-be-truthy)))))
