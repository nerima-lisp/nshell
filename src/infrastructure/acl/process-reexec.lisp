;;; Replacing the running image with a new nshell process (task P0-4).
(in-package #:nshell.infrastructure.acl)

(defun current-executable-path ()
  "Return the path of the running nshell executable, or NIL when this image
was not saved as an executable, as in a development SBCL. An executable built
with SAVE-LISP-AND-DIE :EXECUTABLE T carries its core, so the core and the
runtime are the same file."
  (let ((runtime (and sb-ext:*runtime-pathname*
                      (ignore-errors (truename sb-ext:*runtime-pathname*))))
        (core (and sb-ext:*core-pathname*
                   (ignore-errors (truename sb-ext:*core-pathname*)))))
    (when (and runtime core (equal runtime core))
      (sb-ext:native-namestring runtime))))

(defun current-process-arguments ()
  "Return the arguments of this process, without the program name."
  (rest sb-ext:*posix-argv*))

(defun exec-program (program arguments)
  "Replace this process with PROGRAM run with ARGUMENTS and the environment
child processes receive. Returns only by signalling an error."
  (%with-pty-exec-vectors (argv envp program arguments
                                (external-command-environment))
    ;; As in %PTY-CHILD-EXEC: an ignored disposition would survive execve.
    (sb-sys:enable-interrupt sb-unix:sigpipe :default)
    (%execve program argv envp)
    (error "execve ~a failed (errno ~d)" program (sb-alien:get-errno))))
