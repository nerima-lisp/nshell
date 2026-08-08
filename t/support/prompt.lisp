(in-package #:nshell/test)

(defun current-display-cwd ()
  "Return the prompt cwd display used by the presentation renderer."
  (let ((cwd (namestring (host-kit:getcwd)))
        (home (host-kit:getenv "HOME")))
    (if (and home (nshell.presentation::%home-prefix-p home cwd))
        (concatenate 'string "~" (subseq cwd (length home)))
        cwd)))

(defun current-left-prompt-segments (&key (exit-code 0))
  "Return the left prompt segments for the current test process context."
  (nshell.domain.prompting:render-prompt-model
   (nshell.domain.prompting:make-prompt-model
    :hostname (or (host-kit:hostname) "localhost")
    :cwd (current-display-cwd)
    :exit-code exit-code)))

(defun current-left-prompt-width (&key (exit-code 0))
  "Return the visible width of the current left prompt."
  (nshell.presentation::%segments-visible-width
   (current-left-prompt-segments :exit-code exit-code)))

(defun call-render-prompt (&key (exit-code 0) (duration-ms nil) (terminal-width 80) branch)
  "Render the prompt with deterministic prompt state and return output plus values."
  (let ((nshell.domain.prompting:*git-status-resolver*
          (lambda (dir)
            (declare (ignore dir))
            (values branch nil))))
    (let ((results nil))
      (values
       (with-output-to-string (*standard-output*)
         (setf results
               (multiple-value-list
                (nshell.presentation:render-prompt
                 (nshell.domain.configuration:default-config)
                 exit-code
                 :last-command-duration-ms duration-ms
                 :terminal-width terminal-width))))
       results))))

(defun capture-render-prompt (&key (exit-code 0) (duration-ms nil) (terminal-width 80) branch)
  "Render the prompt with a deterministic git resolver and return the output string."
  (multiple-value-bind (output results)
      (call-render-prompt :exit-code exit-code
                          :duration-ms duration-ms
                          :terminal-width terminal-width
                          :branch branch)
    (declare (ignore results))
    output))
