(in-package #:nshell.presentation)

(defun %active-mouse-selection-range ()
  (when *input-state*
    (let ((anchor (input-state-mouse-selection-anchor *input-state*))
          (end (input-state-mouse-selection-end *input-state*)))
      (when (and (integerp anchor) (integerp end))
        (list (min anchor end) (max anchor end))))))
(defun %active-matching-delimiter-spans (&optional provided-scan-result)
  (when *input-state*
    (let* ((source (input-state-buffer *input-state*))
           (cursor (input-state-cursor-pos *input-state*))
           (reader-context (%repl-reader-context-for-source source))
           (scan-result
             (or provided-scan-result
                 (%repl-input-scan-result source cursor reader-context)))
           (pair
             (find-if
              (lambda (candidate)
                (or (= cursor
                       (first
                        (nshell.domain.parsing:delimiter-pair-open-span
                         candidate)))
                    (= cursor
                       (first
                        (nshell.domain.parsing:delimiter-pair-close-span
                         candidate)))))
              (nshell.domain.parsing:scan-result-delimiter-pairs
               scan-result))))
      (when pair
        (list (nshell.domain.parsing:delimiter-pair-open-span pair)
              (nshell.domain.parsing:delimiter-pair-close-span pair))))))

(defun %completion-pager-row-budget ()
  (let ((terminal-rows
          (handler-case
              (multiple-value-bind (rows columns)
                  (nshell.infrastructure.acl:get-terminal-size)
                (declare (ignore columns))
                (if (and (numberp rows) (plusp rows)) rows 24))
            (error () 24))))
    (max 0 (- terminal-rows (or *prompt-rendered-lines* 0) 1))))

(defun %render-current-completion-results ()
  (let* ((state *input-state*)
         (candidates (and state (input-state-last-candidates state)))
         (pager (and state (input-state-completion-pager state)))
         (row-budget (%completion-pager-row-budget))
         (terminal-width (terminal-width)))
    (when (and candidates
               (null pager)
               (> (completion-render-line-count
                   candidates
                   :terminal-width terminal-width)
                  row-budget))
      (let* ((base-buffer (or (input-state-completion-base-buffer state)
                              (input-state-buffer state)))
             (base-cursor (or (input-state-completion-base-cursor state)
                              (input-state-cursor-pos state)))
             (candidate-index (input-state-completion-index state))
             (selected-index
               (if (and (<= 0 candidate-index)
                        (< candidate-index (length candidates)))
                   candidate-index
                   0)))
        (setf *input-state*
              (copy-input-state-with state :completion-base-buffer base-buffer :completion-base-cursor base-cursor :completion-pager (list :query "" :index selected-index) :suggestion :clear)
              state *input-state*
              pager (input-state-completion-pager state))))
    (when candidates
      (let* ((pager-active-p (not (null pager)))
             (visible-candidates
               (if pager-active-p
                   (completion-pager-filtered-candidates state)
                   candidates))
             (count (length visible-candidates))
             (selected-index
               (if pager-active-p
                   (if (plusp count)
                       (max 0 (min (1- count)
                                   (getf pager :index 0)))
                       0)
                   (input-state-completion-index state)))
             (query (and pager-active-p (getf pager :query "")))
             (footer
               (when pager-active-p
                 (format nil "~a~d/~d  arrows move, Enter accepts, Esc/Ctrl-C cancels"
                         (if (string= query "")
                             ""
                             (format nil "Filter: ~a | " query))
                         (if (plusp count) (1+ selected-index) 0)
                         count))))
        (setf *completion-rendered-lines*
              (%render-transient-output-below-prompt
               (lambda ()
                 (render-completions
                  visible-candidates
                  :selected-index selected-index
                  :terminal-width terminal-width
                  :max-rows row-budget
                  :footer footer
                  :empty-message (when pager-active-p "No matches")
                  :theme (nshell.domain.configuration:config-theme *config*)))))))))

(defun %render-edit-buffer-line
    (line absolute-start theme selection-start selection-end matching-spans
     scan-result cursor-position)
  (loop with local-start = 0
        with line-length = (length line)
        while (< local-start line-length)
        do (let* ((absolute-index (+ absolute-start local-start))
                  (selected-p (and (integerp selection-start)
                                   (integerp selection-end)
                                   (<= selection-start absolute-index)
                                   (< absolute-index selection-end)))
                  (matching-p
                    (some (lambda (span)
                            (= absolute-index (first span)))
                          matching-spans))
                  (local-end
                    (or (loop for candidate from (1+ local-start) below line-length
                              for candidate-index = (+ absolute-start candidate)
                              for candidate-selected-p =
                                (and (integerp selection-start)
                                     (integerp selection-end)
                                     (<= selection-start candidate-index)
                                     (< candidate-index selection-end))
                              for candidate-matching-p =
                                (some (lambda (span)
                                        (= candidate-index (first span)))
                                      matching-spans)
                              when (or (not (eql selected-p candidate-selected-p))
                                       (not (eql matching-p candidate-matching-p)))
                                do (return candidate))
                        line-length))
                  (segment (subseq line local-start local-end)))
             (cond
               (selected-p
                (%write-styled segment :selection theme))
               (matching-p
                (format t "~c[7m~a~c[0m"
                        (code-char 27) segment (code-char 27)))
               (t
                (handler-case
                    (format t "~a"
                            (highlight->ansi
                             (highlight-line
                              segment
                              :scan-result scan-result
                              :cursor-position cursor-position
                              :absolute-start (+ absolute-start local-start))
                             segment theme))
                  (error ()
                    (format t "~a" segment)))))
             (setf local-start local-end))))

(defun render-edit-buffer
    (text theme &key selection-start selection-end matching-spans
                    scan-result cursor-position)
  (loop with start = 0
        with absolute-start = 0
        with first-line = t
        with done = nil
        until done
        do (let ((newline-pos (position #\Newline text :start start)))
             (unless first-line
               (format t "~%")
               (%write-styled "> " :prompt-continuation theme))
             (let ((line (subseq text start (or newline-pos (length text)))))
               (%render-edit-buffer-line
                line absolute-start theme selection-start selection-end
                matching-spans scan-result cursor-position))
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
  ;; A new prompt cycle starts here, after a command ran; per-keystroke redraws
  ;; reuse the git probe so typing never forks git.
  (nshell.infrastructure.acl:clear-git-status-cache)
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
  (let ((transient-panel-content
          (when *preserve-transient-panel-on-next-prompt-p*
            *transient-panel-content*)))
    (setf *preserve-transient-panel-on-next-prompt-p* nil)
    (when (or (%handle-pending-shell-termination)
              (not *running*))
      (return-from render-prompt-cont +repl-exit+))
    (reap-background-jobs)
    (%export-prompt-state)
    (clear-rendered-transient-panel)
    (clear-rendered-search-results)
    (clear-rendered-prompt)
    (when *prompt-hook-pending-p*
      (setf *prompt-hook-pending-p* nil)
      (nshell.application:run-shell-hooks
       :prompt (boundary-current-directory) *last-exit-code*))
    (%ensure-rendered-prompt-origin)
    (let* ((terminal-width (terminal-width))
           (prompt-width
             (progn
               (when (and *interactive-terminal-installed-p*
                          (eq *osc133-state* :none))
                 (%emit-terminal-integration-sequence
                  :osc7
                  (boundary-current-directory)
                  (boundary-hostname))
                 (%emit-terminal-integration-sequence :osc133 "A")
                 (setf *osc133-state* :prompt))
               (render-prompt *config* *last-exit-code*
                              :last-command-duration-ms *last-command-duration-ms*
                              :failure-explain-p *failure-explain-available-p*
                              :terminal-width terminal-width
                              :window-title-p
                              (and *interactive-terminal-installed-p*
                                   (eq *osc133-state* :prompt)))))
           (text (input-state-buffer *input-state*))
           (cursor-position (input-state-cursor-pos *input-state*))
           (reader-context (%repl-reader-context-for-source text))
           (scan-result
             (%repl-input-scan-result text cursor-position reader-context))
           (highlight-scan-result
             (and (eq reader-context :sexp) scan-result))
           (theme (nshell.domain.configuration:config-theme *config*))
           (suggestion (input-state-suggestion *input-state*))
           (ask-suffix (when (member (input-state-mode *input-state*)
                                     '(:ask :ask-waiting)
                                     :test #'eq)
                        "ask>"))
           (selection-range (%active-mouse-selection-range))
           (matching-spans (%active-matching-delimiter-spans scan-result)))
      (when ask-suffix
        (format t " ")
        (%write-styled ask-suffix :prompt-assistant theme)
        (incf prompt-width (1+ (%string-visible-width ask-suffix))))
      (progn
        (when (eq *osc133-state* :prompt)
          (%emit-terminal-integration-sequence :osc133 "B")
          (setf *osc133-state* :input))
        (render-edit-buffer
         text theme
         :selection-start (first selection-range)
         :selection-end (second selection-range)
         :matching-spans matching-spans
         :scan-result highlight-scan-result
         :cursor-position cursor-position))
      (when (and suggestion (> (length suggestion) 0))
        (%write-styled suggestion :autosuggestion theme))
      (%move-cursor-to-rendered-position text
                                         (input-state-cursor-pos *input-state*)
                                         prompt-width
                                         suggestion
                                         nil
                                         :terminal-width terminal-width)
      (let ((cursor-position
              (%rendered-buffer-position text
                                         (input-state-cursor-pos *input-state*)
                                         prompt-width
                                         :terminal-width terminal-width)))
        (setf *prompt-rendered-lines*
              (%rendered-buffer-line-count text
                                           :suggestion suggestion
                                           :search-suffix nil
                                           :terminal-width terminal-width
                                           :prompt-width prompt-width)
              *prompt-rendered-cursor-row* (rendered-position-row cursor-position)
              *prompt-rendered-terminal-width* terminal-width
              *prompt-rendered-prompt-width* prompt-width)))
    (when transient-panel-content
      (render-transient-panel transient-panel-content
                              :terminal-width (terminal-width)))
    (progn
      (when (eq (input-state-mode *input-state*) :search)
        (render-current-history-search-panel))
      (%render-current-completion-results))
    (when *interactive-terminal-installed-p*
      (if *vi-mode-enabled*
          (nshell.infrastructure.terminal:ansi-set-vi-mode-cursor-shape
           (eq (input-state-mode *input-state*) :insert))
          (write-string (cl-tty-kit:ansi-set-cursor-style :default))))
    (finish-output)
    (lambda () (read-key-cont))))
