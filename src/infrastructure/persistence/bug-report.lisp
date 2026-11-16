;;; Facts for the `nshell bug-report` draft (task P0-6, design decision D-54).
;;; This file reads the environment, the configuration and crash log
;;; directories, and the terminal; NSHELL.DOMAIN.BUG-REPORT decides what of it
;;; is printed.
(in-package #:nshell.infrastructure.persistence)

(defun %bug-report-terminal-width ()
  "Return the column count of the first of stdout, stderr, and stdin that is a
terminal, or NIL. The draft is usually redirected to a file, so stdout alone
would rarely answer."
  (loop for fd in '(1 2 0)
        do (handler-case
               (return (nth-value 1 (nshell.infrastructure.acl:get-terminal-size fd)))
             (nshell.infrastructure.acl:terminal-size-unavailable () nil))))

(defun %bug-report-file-fact (path)
  "Return the configuration file fact for the native namestring PATH. The file
is opened only after stat says it is a regular file, so a FIFO cannot block
the report."
  (let ((stat (handler-case (sb-posix:stat path)
                (sb-posix:syscall-error () nil))))
    (cond
      ((null stat)
       (if (handler-case (progn (sb-posix:lstat path) t)
             (sb-posix:syscall-error () nil))
           ;; A dangling symlink, or a path stat may not traverse.
           (nshell.domain.bug-report:make-config-file-fact :unreadable)
           (nshell.domain.bug-report:make-config-file-fact :absent)))
      ((not (sb-posix:s-isreg (sb-posix:stat-mode stat)))
       (nshell.domain.bug-report:make-config-file-fact :not-regular))
      (t
       (handler-case
           (with-open-file (stream (sb-ext:parse-native-namestring path)
                                   :element-type '(unsigned-byte 8))
             (let ((octets (make-array (file-length stream)
                                       :element-type '(unsigned-byte 8))))
               (read-sequence octets stream)
               (nshell.domain.bug-report:make-config-file-fact
                :present
                :size (length octets)
                :sha256 (nshell.domain.bug-report:sha256-hex octets))))
         ((or file-error stream-error) ()
           (nshell.domain.bug-report:make-config-file-fact
            :unreadable :size (sb-posix:stat-size stat))))))))

(defun %bug-report-directory-file-names (directory type)
  "Return the names of the files directly in DIRECTORY whose type is exactly
TYPE, sorted, or NIL when DIRECTORY cannot be listed. Subdirectories are left
out, as the configuration loader leaves them out."
  (handler-case
      (sort (loop for path in (directory
                               (merge-pathnames
                                (make-pathname :name :wild :type type)
                                (sb-ext:parse-native-namestring
                                 directory nil *default-pathname-defaults*
                                 :as-directory t))
                               :resolve-symlinks nil)
                  when (and (pathname-name path)
                            (equal (pathname-type path) type))
                    collect (file-namestring path))
            #'string<)
    (file-error () nil)))

(defun %bug-report-directory-facts (directory type)
  (loop for name in (%bug-report-directory-file-names directory type)
        collect (%bug-report-file-fact (concatenate 'string directory name))))

(defun %bug-report-dependencies ()
  "Return (NAME . VERSION) for each system nshell depends on, in the order
nshell.asd lists them."
  (loop for dependency in (asdf:system-depends-on (asdf:find-system "nshell"))
        when (stringp dependency)
          collect (cons dependency
                        (let ((system (asdf:find-system dependency nil)))
                          (and system (asdf:component-version system))))))

(defun bug-report-text (&key (environment
                              (nshell.infrastructure.acl:current-environment-entries))
                             (terminal-width (%bug-report-terminal-width)))
  "Return the `nshell bug-report` draft for ENVIRONMENT, a list of
\"NAME=VALUE\" strings that defaults to the process environment. Tests pass
their own ENVIRONMENT, with HOME and the XDG directories pointing at a fixture,
instead of changing the process environment."
  (let* ((variables (nshell.domain.bug-report:parse-environment-entries
                     environment))
         (home (let ((value (cdr (assoc "HOME" variables :test #'string=))))
                 (if (and value (plusp (length value)))
                     value
                     (namestring (user-homedir-pathname)))))
         (xdg-config-home (cdr (assoc "XDG_CONFIG_HOME" variables :test #'string=)))
         (xdg-state-home (cdr (assoc "XDG_STATE_HOME" variables :test #'string=)))
         (config-directory (nshell.domain.bug-report:config-directory
                            xdg-config-home home))
         (crash-directory (nshell.domain.crash:crash-log-directory
                           xdg-state-home home)))
    (nshell.domain.bug-report:render-bug-report
     :version (asdf:component-version (asdf:find-system "nshell"))
     :lisp-version (format nil "~a ~a"
                           (lisp-implementation-type)
                           (lisp-implementation-version))
     ;; SOFTWARE-VERSION is the kernel release; MACHINE-INSTANCE, the host
     ;; name, is never used.
     :os (format nil "~a ~a" (software-type) (software-version))
     :architecture (machine-type)
     :terminal-width terminal-width
     :environment variables
     :home home
     :config-label (nshell.domain.bug-report:config-directory-label xdg-config-home)
     :init-file (%bug-report-file-fact
                 (concatenate 'string config-directory "init.lisp"))
     :conf-files (%bug-report-directory-facts
                  (concatenate 'string config-directory "conf.d/") "lisp")
     :function-files (%bug-report-directory-facts
                      (concatenate 'string config-directory "functions/") "nsh")
     :crash-label (nshell.domain.bug-report:crash-log-directory-label xdg-state-home)
     :crash-log-names (%bug-report-directory-file-names crash-directory "log")
     :dependencies (%bug-report-dependencies))))
