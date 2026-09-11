(in-package #:nshell/test)

(defparameter +prompt-test-hostname+ "test-host"
  "Fixed hostname for prompt-rendering tests, so width arithmetic does not
depend on the real machine's (possibly long) hostname.")

(defparameter +prompt-test-cwd+ #P"/project/"
  "Fixed working directory for prompt-rendering tests: deliberately a single
path component, so fish-style shortening (which only ever cuts a component
other than the last) can never change its displayed text, whatever terminal
width a given test happens to derive. Path-shortening itself is tested
directly against %DISPLAY-CWD with deeper, purpose-built paths instead of
through this fixture.")

(defmacro with-prompt-test-boundaries ((&key remote-session-p user) &body body)
  "Run BODY with a short, fixed hostname and working directory standing in
for the real machine, and the remote-session/user hooks forced to
REMOTE-SESSION-P/USER (NIL by default), so prompt-width tests are
deterministic regardless of where the test process happens to run (a real
SSH session, or a long ambient cwd or hostname, would otherwise change the
rendered layout)."
  `(let ((nshell.presentation::*boundaries*
           (cl-boundary-kit:make-boundary-context
            :host-info (cl-boundary-kit:make-test-host-info
                        :hostname +prompt-test-hostname+)
            :working-dir (cl-boundary-kit:make-test-working-directory
                          :initial +prompt-test-cwd+)))
         (nshell.presentation::*prompt-remote-session-p* (lambda () ,remote-session-p))
         (nshell.presentation::*prompt-user* (lambda () ,user)))
     ,@body))

(defun current-display-cwd (&optional (terminal-width 1000))
  "Return the prompt cwd display render-prompt would produce for the fixed
test working directory. TERMINAL-WIDTH defaults wide enough that fish-style
shortening never engages."
  (nshell.presentation::%display-cwd (namestring +prompt-test-cwd+) terminal-width))

(defun current-left-prompt-segments (&key (exit-code 0) branch dirty (terminal-width 1000)
                                          remote-session-p user)
  "Return the left prompt segments for the fixed test boundaries. TERMINAL-WIDTH
defaults wide enough that fish-style path shortening never engages."
  (with-prompt-test-boundaries (:remote-session-p remote-session-p :user user)
    (let ((nshell.domain.prompting:*git-status-resolver*
            (lambda (dir)
              (declare (ignore dir))
              (values branch dirty))))
      (nshell.domain.prompting:render-prompt-model
       (nshell.presentation::%current-prompt-model exit-code nil terminal-width)))))

(defun current-left-prompt-width (&key (exit-code 0) branch dirty (terminal-width 1000)
                                       remote-session-p user)
  "Return the visible width of the current left prompt."
  (nshell.presentation::%segments-visible-width
   (current-left-prompt-segments :exit-code exit-code :branch branch :dirty dirty
                                 :terminal-width terminal-width
                                 :remote-session-p remote-session-p :user user)))

(defun call-render-prompt (&key (exit-code 0) (duration-ms nil)
                                (failure-explain-p nil)
                                (terminal-width 80) branch dirty
                                remote-session-p user window-title-p)
  "Render the prompt with deterministic prompt state and return output plus values."
  (with-prompt-test-boundaries (:remote-session-p remote-session-p :user user)
    (let ((nshell.domain.prompting:*git-status-resolver*
            (lambda (dir)
              (declare (ignore dir))
              (values branch dirty))))
      (let ((results nil))
        (values
         (with-output-to-string (*standard-output*)
           (setf results
                 (multiple-value-list
                  (nshell.presentation:render-prompt
                   (nshell.domain.configuration:default-config)
                   exit-code
                   :last-command-duration-ms duration-ms
                   :failure-explain-p failure-explain-p
                   :terminal-width terminal-width
                   :window-title-p window-title-p))))
         results)))))

(defun capture-render-prompt (&key (exit-code 0) (duration-ms nil)
                                   (failure-explain-p nil)
                                   (terminal-width 80) branch dirty
                                   remote-session-p user window-title-p)
  "Render the prompt with a deterministic git resolver and return the output string."
  (multiple-value-bind (output results)
      (call-render-prompt :exit-code exit-code
                          :duration-ms duration-ms
                          :failure-explain-p failure-explain-p
                          :terminal-width terminal-width
                          :branch branch
                          :dirty dirty
                          :remote-session-p remote-session-p
                          :user user
                          :window-title-p window-title-p)
    (declare (ignore results))
    output))
