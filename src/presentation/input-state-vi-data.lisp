;;; Data helpers for vi-mode input-state transitions.

(in-package #:nshell.presentation)

(define-value-struct vi-input-transition
    ((state nil)
     (output :none :type symbol))
  :constructor %make-vi-input-transition)

(defun %vi-clear-count (state)
  (copy-input-state-with state :vi-count nil))

(defun vi-input-transition (state output)
  (%make-vi-input-transition state output))

(defun vi-input-transition-clearing-count (state output)
  (vi-input-transition (%vi-clear-count state) output))

(defun commit-vi-input-transition (transition)
  (values (vi-input-transition-state transition)
          (vi-input-transition-output transition)))

(define-value-struct vi-visual-selection
    ((start 0 :type fixnum)
     (end 0 :type fixnum)
     (cursor 0 :type fixnum)))

(define-value-struct vi-operator-edit
    ((start 0 :type fixnum)
     (end 0 :type fixnum)
     (cursor 0 :type fixnum)
     (end-mode :vi-command :type (member :vi-command :insert))))

(defun %vi-visual-range (state)
  (let* ((buffer (input-state-buffer state))
         (anchor (or (input-state-vi-visual-anchor state)
                     (input-state-cursor-pos state)))
         (cursor (input-state-cursor-pos state))
         (start (min anchor cursor))
         (end (min (length buffer) (1+ (max anchor cursor)))))
    (values start end)))

(defun vi-visual-selection-for-state (state)
  (multiple-value-bind (start end)
      (%vi-visual-range state)
    (%make-vi-visual-selection start end start)))

(define-value-struct vi-visual-yank-edit
    ((cursor 0 :type fixnum)
     (selected "" :type string)))

(defun vi-visual-yank-edit-for-range (state start end cursor)
  (let* ((buffer (input-state-buffer state))
         (start (max 0 (min start (length buffer))))
         (end (max start (min end (length buffer))))
         (cursor (max 0 (min cursor (length buffer)))))
    (%make-vi-visual-yank-edit cursor (subseq buffer start end))))

(define-value-struct vi-visual-anchor-swap-edit
    ((cursor 0 :type fixnum)
     (anchor 0 :type fixnum)))

(defun vi-visual-anchor-swap-edit-for-state (state)
  (%make-vi-visual-anchor-swap-edit
   (input-state-cursor-pos state)
   (or (input-state-vi-visual-anchor state)
       (input-state-cursor-pos state))))
(progn
  (defun %vi-session-value (state key &optional default)
    (getf (input-state-vi-session state) key default))
  (defun %vi-session-plist-with (state &rest overrides)
    (let ((session (copy-list (input-state-vi-session state))))
      (loop for (key value) on overrides by (function cddr)
            do (setf (getf session key) value))
      session))

  (defun %vi-session-with (state &rest overrides)
    (copy-input-state-with
     state
     :vi-session
     (apply (function %vi-session-plist-with) state overrides)))
  (defun %vi-snapshot (state)
    (list :buffer (input-state-buffer state)
          :cursor-pos (input-state-cursor-pos state)))
  (defun %vi-restore-snapshot (state snapshot)
    (copy-input-state-with state
                           :buffer (getf snapshot :buffer)
                           :cursor-pos (getf snapshot :cursor-pos)
                           :mode :vi-command
                           :vi-count nil
                           :vi-visual-anchor :clear
                           :vi-session (%vi-session-plist-with state
                           :pending nil
                           :operator nil
                           :recording-change nil
                           :change-origin nil
                           :count-events nil)))
  (defun %vi-next-position (buffer position)
    (if (< position (length buffer))
        (%next-grapheme-boundary buffer position)
        (length buffer)))
  (defun %vi-previous-position (buffer position)
    (if (plusp position)
        (%previous-grapheme-boundary buffer position)
        0))
  (defun %vi-counted-next-position (buffer position count)
    (%vi-counted-position position count
                          (lambda (current)
                            (%vi-next-position buffer current))))
  (defun %vi-counted-previous-position (buffer position count)
    (%vi-counted-position position count
                          (lambda (current)
                            (%vi-previous-position buffer current))))
  (defun %vi-line-start (buffer position)
    (1+ (or (position #\Newline buffer :end (min position (length buffer))
                      :from-end t)
            -1)))
  (defun %vi-line-end (buffer position)
    (or (position #\Newline buffer
                  :start (min position (length buffer)))
        (length buffer)))
  (defun %vi-line-range (buffer position)
    (values (%vi-line-start buffer position)
            (%vi-line-end buffer position)))
  (defun %vi-line-starts (buffer)
    (cons 0
          (loop for position from 0 below (length buffer)
                when (char= (char buffer position) #\Newline)
                  collect (1+ position))))
  (defun %vi-line-position (buffer line-number)
    (let* ((starts (%vi-line-starts buffer))
           (index (max 0 (min (1- (length starts))
                              (1- (max 1 line-number)))))
           (position (nth index starts)))
      position))
  (defun %vi-grapheme-floor (buffer position)
    (loop with start = 0
          for grapheme in (cl-tty-kit:string-graphemes buffer)
          for end = (+ start (length grapheme))
          do (cond
               ((= position start) (return position))
               ((< position end) (return start))
               (t (setf start end)))
          finally (return (length buffer))))
  (defun %vi-grapheme-ceiling (buffer position)
    (loop with start = 0
          for grapheme in (cl-tty-kit:string-graphemes buffer)
          for end = (+ start (length grapheme))
          do (cond
               ((<= position start) (return position))
               ((< position end) (return end))
               (t (setf start end)))
          finally (return (length buffer))))
  (defun %vi-unescaped-char-p (buffer position line-start)
    (let ((slashes 0))
      (loop for index downfrom (1- position) to line-start
            while (char= (char buffer index) #\\)
            do (incf slashes))
      (evenp slashes)))
  (defun %vi-quote-object-range (buffer cursor quote line-start line-end)
    (let ((opening nil)
          (best nil))
      (loop for position from line-start below line-end
            when (and (char= (char buffer position) quote)
                      (%vi-unescaped-char-p buffer position line-start))
              do (if opening
                     (progn
                       (when (<= opening cursor position)
                         (let ((candidate (list opening (1+ position))))
                           (when (or (null best)
                                     (< (- (second candidate) (first candidate))
                                        (- (second best) (first best))))
                             (setf best candidate))))
                       (setf opening nil))
                     (setf opening position)))
      best))
  (defun %vi-paired-object-range (buffer cursor opening closing line-start line-end)
    (let ((best nil))
      (loop for start from line-start below line-end
            when (char= (char buffer start) opening)
            do (let ((depth 0)
                     (close-position nil))
                 (loop for position from start below line-end
                       until close-position
                       do (let ((character (char buffer position)))
                            (cond
                              ((char= character opening)
                               (incf depth))
                              ((char= character closing)
                               (decf depth)
                               (when (zerop depth)
                                 (setf close-position position))))))
                 (when (and close-position
                            (<= start cursor close-position))
                   (let ((candidate (list start (1+ close-position))))
                     (when (or (null best)
                               (< (- (second candidate) (first candidate))
                                  (- (second best) (first best))))
                       (setf best candidate))))))
      best))
  (defun %vi-word-object-range (buffer cursor around line-start line-end)
    (let* ((range (or (shell-token-range-at-position buffer cursor)
                      (shell-token-range-at-or-after-cursor buffer cursor)
                      (shell-token-range-before-position buffer cursor)))
           (start (and range (%vi-grapheme-floor
                              buffer
                              (shell-token-range-start range))))
           (end (and range (%vi-grapheme-ceiling
                            buffer
                            (shell-token-range-end range)))))
      (when range
        (when around
          (let ((expanded-end end))
            (loop while (and (< expanded-end line-end)
                             (nshell.domain.parsing:shell-token-separator-p
                              (char buffer expanded-end)))
                  do (incf expanded-end))
            (if (> expanded-end end)
                (setf end expanded-end)
                (loop while (and (> start line-start)
                                 (nshell.domain.parsing:shell-token-separator-p
                                  (char buffer (1- start))))
                      do (decf start)))))
        (values start end))))
  (defun %vi-text-object-range (state object-char around)
    (let* ((buffer (input-state-buffer state))
           (cursor (input-state-cursor-pos state)))
      (multiple-value-bind (line-start line-end)
          (%vi-line-range buffer cursor)
        (case object-char
          (#\w (%vi-word-object-range buffer cursor around line-start line-end))
          ((#\' #\")
           (let ((range (%vi-quote-object-range buffer cursor object-char
                                                line-start line-end)))
             (when range
               (if around
                   (values (first range) (second range))
                   (values (1+ (first range)) (1- (second range)))))))
          ((#\( #\))
           (let ((range (%vi-paired-object-range buffer cursor #\( #\)
                                                 line-start line-end)))
             (when range
               (if around
                   (values (first range) (second range))
                   (values (1+ (first range)) (1- (second range)))))))
          ((#\[ #\])
           (let ((range (%vi-paired-object-range buffer cursor #\[ #\]
                                                 line-start line-end)))
             (when range
               (if around
                   (values (first range) (second range))
                   (values (1+ (first range)) (1- (second range)))))))
          ((#\{ #\})
           (let ((range (%vi-paired-object-range buffer cursor #\{ #\}
                                                 line-start line-end)))
             (when range
               (if around
                   (values (first range) (second range))
                   (values (1+ (first range)) (1- (second range)))))))
          (otherwise (values nil nil)))))))
