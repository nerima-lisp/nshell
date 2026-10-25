(in-package #:nshell/test)

(describe "file-config-tests"
  (it "file-config-default-path"
    "The public config path matches the default when no override is set."
    (let ((nshell.infrastructure.persistence::*config-file-path-override* nil))
      (expect (nshell.infrastructure.persistence::%default-config-file-path)
              :to-equal
              (nshell.infrastructure.persistence:config-file-path))))

  (it "file-config-missing-file"
    "Loading a missing config file returns NIL."
    (let* ((test-path (format nil "/tmp/nshell-test-config-missing-~d.lisp"
                              (random 1000000))))
      (unwind-protect
           (progn
             (setf nshell.infrastructure.persistence::*config-file-path-override*
                   (pathname test-path))
             (when (probe-file test-path)
               (delete-file test-path))
             (expect (nshell.infrastructure.persistence:load-config) :to-be-null))
        (setf nshell.infrastructure.persistence::*config-file-path-override* nil)
        (when (probe-file test-path)
          (delete-file test-path)))))

  (it "file-config-roundtrip"
    "Saving and loading config preserves the stored lines."
    (let* ((test-path (format nil "/tmp/nshell-test-config-~d.lisp"
                              (random 1000000)))
           (config '("set -g prompt nshell"
                     "export PATH=/usr/local/bin:$PATH"
                     "")))
      (unwind-protect
           (progn
             (setf nshell.infrastructure.persistence::*config-file-path-override*
                   (pathname test-path))
             (when (probe-file test-path)
               (delete-file test-path))
             (expect t :to-be (nshell.infrastructure.persistence:save-config config))
             (expect config :to-equal (nshell.infrastructure.persistence:load-config)))
        (setf nshell.infrastructure.persistence::*config-file-path-override* nil)
        (when (probe-file test-path)
          (delete-file test-path)))))

  (it "interactive-startup-sources-config"
    "Interactive initialization applies the setting from the selected config file."
    (let* ((config-path (format nil "/tmp/nshell-test-startup-config-~d.lisp"
                                (random 1000000)))
           (history-path (format nil "/tmp/nshell-test-startup-history-~d"
                                 (random 1000000))))
      (unwind-protect
           (progn
             (with-open-file (stream config-path
                                      :direction :output
                                      :if-exists :supersede
                                      :if-does-not-exist :create)
               (write-line "set -x NSHELL_CONFIG_LOADED yes" stream))
             (setf nshell.infrastructure.persistence::*config-file-path-override*
                   (pathname config-path)
                   nshell.infrastructure.persistence::*history-file-path-override*
                   (pathname history-path))
             (nshell.presentation::initialize-repl-state)
             (expect "yes" :to-equal (repl-test-env "NSHELL_CONFIG_LOADED")))
        (setf nshell.infrastructure.persistence::*config-file-path-override* nil
              nshell.infrastructure.persistence::*history-file-path-override* nil)
        (when (probe-file config-path)
          (delete-file config-path))
        (when (probe-file history-path)
          (delete-file history-path)))))
  (it "interactive-config-reports-nonzero-status"
    "A nonzero sourced config status is reported on standard error."
    (with-temporary-functions
        (((quote nshell.infrastructure.persistence:load-config-sources)
          (lambda () (list (cons (nshell.infrastructure.persistence:config-file-path) (list "ignored")))))
         ((quote nshell.presentation::%execute-with-repl-shell-context)
          (lambda (thunk)
            (declare (ignore thunk))
            (values nil 7))))
      (let* ((nshell.presentation::*running* t)
             (message
              (with-output-to-string (*error-output*)
                (nshell.presentation::%load-interactive-config))))
        (expect
         (format nil
                 "nshell: ~a exited with status 7~%"
                 (namestring
                  (nshell.infrastructure.persistence:config-file-path)))
         :to-equal
         message))))
  (it "interactive-config-reports-loading-errors"
    "An error while loading the selected config is reported on standard error."
    (with-temporary-function
        ((quote nshell.infrastructure.persistence:load-config-sources)
         (lambda () (error "broken config")))
      (let ((message
              (with-output-to-string (*error-output*)
                (nshell.presentation::%load-interactive-config))))
        (expect (format nil "nshell: ~a: broken config~%" (namestring (nshell.infrastructure.persistence:config-file-path))) :to-equal message))))
  (it "file-config-xdg-path-and-override"
    "The public config path follows XDG_CONFIG_HOME and explicit overrides."
    (let* ((old-home
             (nshell.infrastructure.acl:current-environment-value "HOME"))
           (old-xdg
             (nshell.infrastructure.acl:current-environment-value
              "XDG_CONFIG_HOME"))
           (home (format nil "/tmp/nshell-config-home-~d/" (random 1000000)))
           (xdg (format nil "/tmp/nshell-config-xdg-~d/" (random 1000000))))
      (unwind-protect
           (progn
             (sb-posix:setenv "HOME" home 1)
             (sb-posix:setenv "XDG_CONFIG_HOME" xdg 1)
             (expect (merge-pathnames #P"nshell/init.lisp"
                                      (uiop:ensure-directory-pathname xdg))
                     :to-equal
                     (nshell.infrastructure.persistence:config-file-path))
             (sb-posix:setenv "XDG_CONFIG_HOME" "" 1)
             (expect (merge-pathnames #P".config/nshell/init.lisp"
                                      (user-homedir-pathname))
                     :to-equal
                     (nshell.infrastructure.persistence:config-file-path))
             (sb-posix:setenv "XDG_CONFIG_HOME" "relative/config" 1)
             (expect (merge-pathnames #P".config/nshell/init.lisp"
                                      (user-homedir-pathname))
                     :to-equal
                     (nshell.infrastructure.persistence:config-file-path))
             (let ((nshell.infrastructure.persistence::*config-file-path-override*
                     #P"/tmp/nshell-explicit-config.lisp"))
               (expect #P"/tmp/nshell-explicit-config.lisp"
                       :to-equal
                       (nshell.infrastructure.persistence:config-file-path))))
        (if old-home
            (sb-posix:setenv "HOME" old-home 1)
            (sb-posix:unsetenv "HOME"))
        (if old-xdg
            (sb-posix:setenv "XDG_CONFIG_HOME" old-xdg 1)
            (sb-posix:unsetenv "XDG_CONFIG_HOME")))))
  (it "file-config-legacy-notice-is-single-line"
    "The legacy rc notice stays on one line while the selected XDG config loads."
    (let* ((old-home
             (nshell.infrastructure.acl:current-environment-value "HOME"))
           (old-xdg
             (nshell.infrastructure.acl:current-environment-value
              "XDG_CONFIG_HOME"))
           (home (format nil "/tmp/nshell-config-legacy-home-~d/"
                         (random 1000000)))
           (xdg (format nil "/tmp/nshell-config-legacy-~d~%/"
                        (random 1000000)))
           (legacy (merge-pathnames ".nshellrc" (pathname home)))
           (config (merge-pathnames #P"nshell/init.lisp"
                                    (uiop:ensure-directory-pathname xdg))))
      (unwind-protect
           (progn
             (sb-posix:setenv "HOME" home 1)
             (sb-posix:setenv "XDG_CONFIG_HOME" xdg 1)
             (ensure-directories-exist legacy)
             (ensure-directories-exist config)
             (with-open-file (stream legacy :direction :output
                                     :if-exists :supersede
                                     :if-does-not-exist :create)
               (write-line "legacy config" stream))
             (with-open-file (stream config :direction :output
                                     :if-exists :supersede
                                     :if-does-not-exist :create)
               (write-line "xdg config" stream))
             (let* ((nshell.infrastructure.persistence::*config-file-path-override*
                      nil)
                    (capture (make-string-output-stream))
                    (loaded (let ((*error-output* capture))
                              (nshell.infrastructure.persistence:load-config)))
                    (notice (get-output-stream-string capture)))
               (expect '("xdg config") :to-equal loaded)
               (expect (search "legacy ~/.nshellrc found" notice) :to-be-truthy)
               (expect 1 :to-equal (count (code-char 10) notice))))
        (if old-home
            (sb-posix:setenv "HOME" old-home 1)
            (sb-posix:unsetenv "HOME"))
        (if old-xdg
            (sb-posix:setenv "XDG_CONFIG_HOME" old-xdg 1)
            (sb-posix:unsetenv "XDG_CONFIG_HOME"))
        (when (probe-file config)
          (delete-file config))
        (when (probe-file legacy)
          (delete-file legacy))
        (ignore-errors
          (sb-posix:rmdir
           (namestring
            (merge-pathnames #P"nshell/"
                             (uiop:ensure-directory-pathname xdg)))))
        (ignore-errors
          (sb-posix:rmdir (namestring (uiop:ensure-directory-pathname xdg))))
        (ignore-errors
          (sb-posix:rmdir (namestring (uiop:ensure-directory-pathname home))))))))
(describe "file-config-order-tests"
  (it "interactive-config-sources-init-before-sorted-conf-d"
    "The XDG init file loads before lowercase conf.d files in sorted filename order."
    (let* ((old-home
             (nshell.infrastructure.acl:current-environment-value "HOME"))
           (old-xdg
             (nshell.infrastructure.acl:current-environment-value
              "XDG_CONFIG_HOME"))
           (old-override
             nshell.infrastructure.persistence::*config-file-path-override*)
           (home (format nil "/tmp/nshell-config-order-home-~d/"
                         (random 1000000)))
           (xdg (format nil "/tmp/nshell-config-order-xdg-~d/"
                        (random 1000000)))
           (xdg-directory
             (uiop:ensure-directory-pathname (pathname xdg)))
           (nshell-directory (merge-pathnames #P"nshell/" xdg-directory))
           (conf-directory (merge-pathnames #P"conf.d/" nshell-directory))
           (init-path (merge-pathnames #P"init.lisp" nshell-directory))
           (first-path (merge-pathnames #P"10-first.lisp" conf-directory))
           (second-path (merge-pathnames #P"20-second.lisp" conf-directory))
           (ignored-path (merge-pathnames #P"15-ignored.txt" conf-directory))
           (ignored-uppercase-path
             (merge-pathnames #P"15-ignored.LISP" conf-directory)))
      (unwind-protect
           (progn
             (sb-posix:setenv "HOME" home 1)
             (sb-posix:setenv "XDG_CONFIG_HOME" xdg 1)
             (setf nshell.infrastructure.persistence::*config-file-path-override*
                   nil)
             (dolist (entry
                      (list (cons init-path "init")
                            (cons second-path "second")
                            (cons first-path "first")
                            (cons ignored-path "ignored")
                            (cons ignored-uppercase-path "uppercase")))
               (ensure-directories-exist (car entry))
               (with-open-file (stream (car entry)
                                       :direction :output
                                       :if-exists :supersede
                                       :if-does-not-exist :create)
                 (write-line (cdr entry) stream)))
             (let ((source-paths nil))
               (with-temporary-function
                ((quote nshell.application:source-lines-to-stream)
                 (lambda (context lines source-path)
                   (declare (ignore context lines))
                   (push source-path source-paths)
                   (values nil 0)))
                (nshell.presentation::initialize-repl-state :history-p nil))
               (expect
                (mapcar (lambda (path)
                          (namestring (truename path)))
                        (list init-path first-path second-path))
                :to-equal
                (mapcar (lambda (path)
                          (namestring (truename path)))
                        (nreverse source-paths))))
             (let ((config-lines nil))
               (with-output-to-string (*error-output*)
                 (setf config-lines
                       (nshell.infrastructure.persistence:load-config)))
               (expect (list "init" "first" "second")
                       :to-equal
                       config-lines)))
        (setf nshell.infrastructure.persistence::*config-file-path-override*
              old-override)
        (if old-home
            (sb-posix:setenv "HOME" old-home 1)
            (sb-posix:unsetenv "HOME"))
        (if old-xdg
            (sb-posix:setenv "XDG_CONFIG_HOME" old-xdg 1)
            (sb-posix:unsetenv "XDG_CONFIG_HOME"))
        (dolist (path (list init-path first-path second-path ignored-path
                            ignored-uppercase-path))
          (when (probe-file path)
            (delete-file path)))
        (dolist (directory
                 (list conf-directory nshell-directory xdg-directory
                       (uiop:ensure-directory-pathname (pathname home))))
          (ignore-errors (sb-posix:rmdir (namestring directory))))))))
