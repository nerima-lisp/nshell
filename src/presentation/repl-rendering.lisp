(in-package #:nshell.presentation)

(defun render-edit-buffer (text theme)
  (loop with start = 0
        with first-line = t
        with done = nil
        until done
        do (let ((newline-pos (position #\Newline text :start start)))
             (unless first-line
               (format t "~%> "))
             (handler-case
                 (let ((line (subseq text start (or newline-pos (length text)))))
                   (format t "~a" (highlight->ansi (highlight-line line) line theme)))
               (error ()
                 (format t "~a" (subseq text start (or newline-pos (length text))))))
             (setf first-line nil)
             (if newline-pos
                 (setf start (1+ newline-pos))
                 (setf done t)))))

(defun reset-rendered-prompt-state ()
  (setf *prompt-rendered-lines* 0
        *prompt-rendered-cursor-row* 0))

(defun clear-rendered-prompt ()
  (if (> *prompt-rendered-lines* 0)
      (let ((rows-below (max 0
                             (- (1- *prompt-rendered-lines*)
                                *prompt-rendered-cursor-row*))))
        (format t "~C" #\Return)
        (when (plusp rows-below)
          (nshell.infrastructure.terminal:ansi-cursor-down rows-below))
        (nshell.infrastructure.terminal:ansi-clear-line)
        (loop repeat (1- *prompt-rendered-lines*)
              do
          (format t "~C[A" #\Esc)
          (nshell.infrastructure.terminal:ansi-clear-line))
        (reset-rendered-prompt-state))
      (progn
        (nshell.infrastructure.terminal:ansi-clear-line)
        (format t "~C" #\Return))))

(defun render-prompt-cont ()
  (unless *running*
    (return-from render-prompt-cont nil))
  (reap-background-jobs)
  (clear-rendered-prompt)
  (let* ((terminal-width
           (multiple-value-bind (rows cols)
               (handler-case (nshell.infrastructure.acl:get-terminal-size)
                 (error () (values 24 80)))
             (declare (ignore rows))
             cols))
         (prompt-width
           (render-prompt *config* *last-exit-code*
                          :last-command-duration-ms *last-command-duration-ms*
                          :terminal-width terminal-width))
         (text (input-state-buffer *input-state*))
         (theme (nshell.domain.configuration:config-theme *config*))
         (suggestion (input-state-suggestion *input-state*))
         (search-query (input-state-search-query *input-state*))
         (search-suffix (when (eq (input-state-mode *input-state*) :search)
                          (format nil " history: ~a" search-query))))
    (render-edit-buffer text theme)
    (when (and suggestion (> (length suggestion) 0))
      (nshell.infrastructure.terminal:ansi-dim)
      (format t "~a" suggestion)
      (nshell.infrastructure.terminal:ansi-reset-style))
    (when search-suffix
      (format t " ")
      (nshell.infrastructure.terminal:ansi-dim)
      (format t "history: ~a" search-query)
      (nshell.infrastructure.terminal:ansi-reset-style))
    (%move-cursor-to-rendered-position text
                                       (input-state-cursor-pos *input-state*)
                                       prompt-width
                                       suggestion
                                       search-suffix
                                       :terminal-width terminal-width)
    (let ((cursor-position
            (%rendered-buffer-position text
                                       (input-state-cursor-pos *input-state*)
                                       prompt-width
                                       :terminal-width terminal-width)))
      (setf *prompt-rendered-lines*
            (%rendered-buffer-line-count text
                                         :suggestion suggestion
                                         :search-suffix search-suffix
                                         :terminal-width terminal-width
                                         :prompt-width prompt-width)
            *prompt-rendered-cursor-row* (rendered-position-row cursor-position)))
  (finish-output)
  (lambda () (read-key-cont))))
