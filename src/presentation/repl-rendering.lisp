(in-package #:nshell.presentation)

(defun %active-mouse-selection-range ()
  (when *input-state*
    (let ((anchor (input-state-mouse-selection-anchor *input-state*))
          (end (input-state-mouse-selection-end *input-state*)))
      (when (and (integerp anchor) (integerp end))
        (list (min anchor end) (max anchor end))))))

(defun %render-edit-buffer-line (line absolute-start theme selection-start selection-end)
  (loop with local-start = 0
        with line-length = (length line)
        while (< local-start line-length)
        do (let* ((absolute-index (+ absolute-start local-start))
                  (selected-p (and (integerp selection-start)
                                   (integerp selection-end)
                                   (<= selection-start absolute-index)
                                   (< absolute-index selection-end)))
                  (local-end
                    (or (loop for candidate from (1+ local-start) below line-length
                              for candidate-selected-p =
                                (and (integerp selection-start)
                                     (integerp selection-end)
                                     (<= selection-start
                                         (+ absolute-start candidate))
                                     (< (+ absolute-start candidate)
                                        selection-end))
                              when (not (eql selected-p candidate-selected-p))
                                do (return candidate))
                        line-length))
                  (segment (subseq line local-start local-end)))
             (if selected-p
                 (format t "~C[7m~a~C[27m" #\Esc segment #\Esc)
                 (handler-case
                     (format t "~a"
                             (highlight->ansi (highlight-line segment) segment theme))
                   (error ()
                     (format t "~a" segment))))
             (setf local-start local-end))))

(defun render-edit-buffer (text theme &key selection-start selection-end)
  (loop with start = 0
        with absolute-start = 0
        with first-line = t
        with done = nil
        until done
        do (let ((newline-pos (position #\Newline text :start start)))
             (unless first-line
               (format t "~%> "))
             (let ((line (subseq text start (or newline-pos (length text)))))
               (%render-edit-buffer-line line absolute-start theme
                                         selection-start selection-end))
             (setf first-line nil)
             (if newline-pos
                 (setf start (1+ newline-pos)
                       absolute-start (1+ newline-pos))
                 (setf done t)))))

(defun %reset-rendered-prompt-geometry ()
  (setf *prompt-rendered-lines* 0
        *prompt-rendered-cursor-row* 0
        *prompt-rendered-terminal-width* +default-terminal-width+
        *prompt-rendered-prompt-width* 0))

(defun reset-rendered-prompt-state ()
  (%reset-rendered-prompt-geometry)
  (setf *prompt-rendered-origin-row* 1
        *prompt-rendered-origin-column* 1
        *prompt-rendered-origin-known-p* nil))

(defun %ensure-rendered-prompt-origin ()
  (unless *prompt-rendered-origin-known-p*
    (when *interactive-terminal-installed-p*
      (handler-case
          (multiple-value-bind (row column)
              (nshell.infrastructure.terminal:query-cursor-position)
            (when (and (integerp row)
                       (integerp column)
                       (plusp row)
                       (plusp column))
              (setf *prompt-rendered-origin-row* row
                    *prompt-rendered-origin-column* column))
            (setf *prompt-rendered-origin-known-p* t))
        (error () nil)))
    (unless *prompt-rendered-origin-known-p*
      (setf *prompt-rendered-origin-row* 1
            *prompt-rendered-origin-column* 1
            *prompt-rendered-origin-known-p* t))))

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
        (%reset-rendered-prompt-geometry))
      (progn
        (nshell.infrastructure.terminal:ansi-clear-line)
        (format t "~C" #\Return))))

(defun render-prompt-cont ()
  (unless *running*
    (return-from render-prompt-cont nil))
  (reap-background-jobs)
  (clear-rendered-prompt)
  (%ensure-rendered-prompt-origin)
  (let* ((terminal-width (terminal-width))
         (prompt-width
           (render-prompt *config* *last-exit-code*
                          :last-command-duration-ms *last-command-duration-ms*
                          :terminal-width terminal-width))
         (text (input-state-buffer *input-state*))
         (theme (nshell.domain.configuration:config-theme *config*))
         (suggestion (input-state-suggestion *input-state*))
         (search-query (input-state-search-query *input-state*))
         (search-suffix (when (eq (input-state-mode *input-state*) :search)
                          (format nil " history: ~a" search-query)))
         (selection-range (%active-mouse-selection-range)))
    (render-edit-buffer text theme
                        :selection-start (first selection-range)
                        :selection-end (second selection-range))
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
            *prompt-rendered-cursor-row* (rendered-position-row cursor-position)
            *prompt-rendered-terminal-width* terminal-width
            *prompt-rendered-prompt-width* prompt-width))
  (finish-output)
  (lambda () (read-key-cont))))
