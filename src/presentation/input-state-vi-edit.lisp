;;; Vi edit/reduction logic split out from the base vi input state helpers.

(in-package #:nshell.presentation)

(defun %vi-enter-insert (state &optional position)
  (%vi-insert-state state :cursor-pos position))

(defun %vi-kill-into (state start end cursor end-mode)
  "Kill the buffer span [START, END) (recording it on the kill ring), leave the
cursor at CURSOR, and switch to END-MODE (:vi-command for d, :insert for c)."
  (multiple-value-bind (killed-state output)
      (%kill-range state (max 0 (min start end)) (max start end) cursor)
    (declare (ignore output))
    (values (if (eq end-mode :vi-command)
                (%vi-command-state killed-state :cursor-pos cursor)
                (%vi-insert-state killed-state :cursor-pos cursor))
            :redraw)))

(defun commit-vi-visual-kill-selection (state selection end-mode)
  (%vi-kill-into state
                 (vi-visual-selection-start selection)
                 (vi-visual-selection-end selection)
                 (vi-visual-selection-cursor selection)
                 end-mode))

(defun commit-vi-operator-edit (state edit)
  (%vi-kill-into state
                 (vi-operator-edit-start edit)
                 (vi-operator-edit-end edit)
                 (vi-operator-edit-cursor edit)
                 (vi-operator-edit-end-mode edit)))

(defun %reduce-vi-normal (state ch)
  "Handle a single character CH in vi normal mode."
  (let ((pos (input-state-cursor-pos state))
        (len (%vi-buffer-length state))
        (count (%vi-count state)))
    (%vi-with-common-motion-cases (state ch pos len count)
      ;; Visual selection.
      ((#\v) (values (%vi-enter-visual state) :redraw))
      ;; Enter insert mode.
      ((#\i) (values (%vi-enter-insert state) :redraw))
      ((#\a) (values (%vi-enter-insert state (min len (1+ pos))) :redraw))
      ((#\I) (values (%vi-enter-insert state 0) :redraw))
      ((#\A) (values (%vi-enter-insert state len) :redraw))
      ;; Single-key edits.
      ((#\x) (if (< pos len)
                 (%vi-kill-into state pos (min len (+ pos count)) pos :vi-command)
                 (values state :none)))
      ((#\D) (%vi-kill-into state pos len (max 0 (1- pos)) :vi-command))
      ((#\C) (%vi-kill-into state pos len pos :insert))
      ((#\s) (%vi-kill-into state pos (min len (+ pos count)) pos :insert))
      ;; Operators: remember via a transient mode.
      ((#\d) (values (copy-input-state-with state :mode :vi-d) :redraw))
      ((#\c) (values (copy-input-state-with state :mode :vi-c) :redraw))
      ;; History.
      ((#\j) (%vi-values-clearing-count state :history-next))
      ((#\k) (%vi-values-clearing-count state :history-prev))
      (otherwise (values state :none)))))

(defun %reduce-vi-visual (state ch)
  "Handle a single character CH in vi char-wise visual mode."
  (let ((pos (input-state-cursor-pos state))
        (len (%vi-buffer-length state))
        (count (%vi-count state)))
    (%vi-with-common-motion-cases (state ch pos len count)
      ((#\v) (values (%vi-leave-visual state) :redraw))
      ((#\o) (%vi-swap-visual-anchor state))
      ((#\d #\x)
       (commit-vi-visual-kill-selection
        state (vi-visual-selection-for-state state) :vi-command))
      ((#\c #\s)
       (commit-vi-visual-kill-selection
        state (vi-visual-selection-for-state state) :insert))
      ((#\y)
       (multiple-value-bind (new-state commit-output)
           (commit-vi-visual-yank-selection
            state (vi-visual-selection-for-state state))
         (declare (ignore commit-output))
         (values new-state :copy)))
      ((#\i) (values (%vi-enter-insert (%vi-leave-visual state)) :redraw))
      ((#\a) (values (%vi-enter-insert (%vi-leave-visual state)
                                       (min len (1+ pos)))
                     :redraw))
      (otherwise (values state :none)))))

(defun %reduce-vi-operator (state ch op)
  "Apply operator OP (:d or :c) to the motion keyed by CH."
  (let ((edit (vi-operator-edit-for-motion state ch op)))
    (if edit
        (commit-vi-operator-edit state edit)
        (values (%vi-command-state state) :redraw))))

(progn
  (defvar *vi-replaying-change-p* nil)

  (defun %vi-pending-kind (state)
    (getf (%vi-session-value state :pending) :kind))

  (defun %vi-pending-value (state key &optional default)
    (getf (%vi-session-value state :pending) key default))

  (defun %vi-set-pending (state kind &rest fields)
    (%vi-session-with state
                      :pending (append (list :kind kind) fields)))

  (defun %vi-operator (state)
    (or (%vi-session-value state :operator)
        (case (input-state-mode state)
          (:vi-c :c)
          (otherwise :d))))

  (defun %vi-command-state (state &key cursor-pos clear-completion-p)
    (let ((state (%vi-session-with state :pending nil :operator nil)))
      (%vi-state-with-mode state
                           :vi-command
                           :cursor-pos cursor-pos
                           :anchor :clear
                           :clear-completion-p clear-completion-p)))

  (defun %vi-insert-state (state &key cursor-pos)
    (let ((state (%vi-session-with state :pending nil :operator nil)))
      (%vi-state-with-mode state :insert :cursor-pos cursor-pos :anchor :clear)))

  (defun %vi-state-with-mode (state mode &key cursor-pos anchor clear-completion-p)
    (let ((state (if clear-completion-p
                     (clear-completion-session-state state)
                     state)))
      (copy-input-state-with state
                             :mode mode
                             :vi-count nil
                             :vi-visual-anchor anchor
                             :cursor-pos (or cursor-pos
                                             (input-state-cursor-pos state)))))

  (defun %vi-visual-range (state)
    (let* ((buffer (input-state-buffer state))
           (anchor (or (input-state-vi-visual-anchor state)
                       (input-state-cursor-pos state)))
           (cursor (input-state-cursor-pos state))
           (start (min anchor cursor))
           (last (max anchor cursor))
           (end (if (< last (length buffer))
                    (%vi-next-position buffer last)
                    (length buffer))))
      (values start end)))

  (defun vi-enter-command-mode (state)
    (let* ((buffer (input-state-buffer state))
           (position (%vi-previous-position buffer
                                            (input-state-cursor-pos state))))
      (%vi-command-state state :cursor-pos position :clear-completion-p t)))

  (defun %vi-line-command-position (buffer position)
    (multiple-value-bind (start end) (%vi-line-range buffer position)
      (declare (ignore end))
      start))

  (defun %vi-counted-line-position (state line-number)
    (let* ((buffer (input-state-buffer state))
           (position (%vi-line-position buffer line-number)))
      (%vi-line-command-position buffer position)))

  (defun %vi-current-line-number (buffer position)
    (1+ (count #\Newline buffer :end (min position (length buffer)))))

  (defun %vi-find-target (state motion target-character count)
    (let* ((buffer (input-state-buffer state))
           (cursor (input-state-cursor-pos state))
           (forward-p (member motion '(#\f #\t)))
           (line-start (%vi-line-start buffer cursor))
           (line-end (%vi-line-end buffer cursor))
           (remaining count)
           (scan (if forward-p
                     (%vi-next-position buffer cursor)
                     (%vi-previous-position buffer cursor)))
           (target nil))
      (loop while (if forward-p (< scan line-end) (>= scan line-start))
            do (when (char= (char buffer scan) target-character)
                 (decf remaining)
                 (when (zerop remaining)
                   (setf target scan)
                   (return)))
               (setf scan (if forward-p
                              (%vi-next-position buffer scan)
                              (%vi-previous-position buffer scan))))
      (when target
        (case motion
          (#\t (setf target (%vi-previous-position buffer target)))
          (#\T (setf target (%vi-next-position buffer target)))))
      target))

  (defun %vi-find-motion-type (motion reverse-p)
    (if reverse-p
        (case motion
          (#\f #\F) (#\F #\f) (#\t #\T) (#\T #\t))
        motion))

  (defun %vi-find-operator-edit (state motion target)
    (let* ((buffer (input-state-buffer state))
           (cursor (input-state-cursor-pos state))
           (forward-p (member motion (list #\f #\t)))
           (inclusive-p (member motion (list #\f #\F)))
           (start (if forward-p cursor
                      (if inclusive-p target
                          (%vi-next-position buffer target))))
           (end (if forward-p
                    (if inclusive-p (%vi-next-position buffer target) target)
                    (%vi-next-position buffer cursor)))
           (operator (%vi-operator state))
           (end-mode (if (eq operator :c) :insert :vi-command)))
      (%make-vi-operator-edit start end start end-mode)))

  (defun %vi-yank-text (buffer start end linewise-p)
    (let ((text (subseq buffer start end)))
      (if (and linewise-p
               (or (zerop (length text))
                   (not (char= (char text (1- (length text))) #\Newline))))
          (concatenate 'string text (string #\Newline))
          text)))

  (defun %vi-linewise-operator-range (state count)
    (let* ((buffer (input-state-buffer state))
           (start (%vi-line-start buffer (input-state-cursor-pos state)))
           (starts (%vi-line-starts buffer))
           (line-index (or (position start starts) 0))
           (end-index (+ line-index count))
           (end (if (< end-index (length starts))
                    (nth end-index starts)
                    (length buffer))))
      (values start end)))

  (defun %vi-commit-operator-range (state start end cursor operator linewise-p)
    (let* ((buffer (input-state-buffer state))
           (start (max 0 (min start (length buffer))))
           (end (max start (min end (length buffer))))
           (text (%vi-yank-text buffer start end linewise-p))
           (yank-type (if linewise-p :linewise :characterwise)))
      (cond
        ((eq operator :y)
         (let ((new-state
                 (%vi-command-state
                  (copy-input-state-with
                   state
                   :kill-ring (if (zerop (length text))
                                  (input-state-kill-ring state)
                                  (cons text (input-state-kill-ring state)))
                   :vi-session (%vi-session-plist-with state
                                                 :yank-type yank-type))
                  :cursor-pos cursor
                  :clear-completion-p t)))
           (values new-state (if (zerop (length text)) :none :redraw))))
        ((= start end)
         (if (eq operator :c)
             (values (%vi-insert-state state :cursor-pos cursor) :redraw)
             (values (%vi-command-state state) :none)))
        (t
         (let* ((new-buffer (concatenate 'string
                                         (subseq buffer 0 start)
                                         (subseq buffer end)))
                (new-state
                  (copy-input-state-clearing-completion
                   state
                   :buffer new-buffer
                   :cursor-pos (min cursor start)
                   :mode (if (eq operator :c) :insert :vi-command)
                   :vi-count nil
                   :vi-visual-anchor :clear
                   :kill-ring (cons text (input-state-kill-ring state))
                   :vi-session (%vi-session-plist-with state
                                                 :operator nil
                                                 :pending nil
                                                 :yank-type yank-type))))
           (values new-state :redraw))))))

  (defun vi-operator-edit-for-motion (state ch operator)
    (let* ((buffer (input-state-buffer state))
           (position (input-state-cursor-pos state))
           (count (%vi-count state))
           (line-start (%vi-line-start buffer position))
           (line-end (%vi-line-end buffer position))
           (self (ecase operator (:d #\d) (:c #\c) (:y #\y))))
      (cond
        ((char= ch self)
         (multiple-value-bind (start end)
             (%vi-linewise-operator-range state count)
           (%make-vi-operator-edit start end start
                                   (if (eq operator :c) :insert :vi-command))))
        ((char= ch #\w)
         (%make-vi-operator-edit
          position (%vi-counted-kill-word-end buffer position count)
          position (if (eq operator :c) :insert :vi-command)))
        ((char= ch #\b)
         (let ((start (%vi-counted-kill-word-start buffer position count)))
           (%make-vi-operator-edit start position start
                                   (if (eq operator :c) :insert :vi-command))))
        ((char= ch #\e)
         (let ((last (%vi-counted-word-end-position buffer position count)))
           (%make-vi-operator-edit position
                                   (%vi-next-position buffer last)
                                   position
                                   (if (eq operator :c) :insert :vi-command))))
        ((char= ch #\$)
         (%make-vi-operator-edit
          position line-end
          (if (eq operator :c)
              position
              (if (> position line-start)
                  (%vi-previous-position buffer line-end)
                  line-start))
          (if (eq operator :c) :insert :vi-command)))
        ((char= ch #\0)
         (%make-vi-operator-edit line-start position line-start
                                 (if (eq operator :c) :insert :vi-command)))
        ((char= ch #\G)
         (%make-vi-operator-edit position (length buffer) position
                                 (if (eq operator :c) :insert :vi-command)))
        (t nil))))

  (defun %vi-start-operator (state operator)
    (copy-input-state-with
     state
     :mode (if (eq operator :c) :vi-c :vi-d)
     :vi-session (%vi-session-plist-with state
                                   :operator operator
                                   :pending nil)))

  (defun %vi-apply-operator-edit (state edit operator linewise-p)
    (%vi-commit-operator-range state
                               (vi-operator-edit-start edit)
                               (vi-operator-edit-end edit)
                               (vi-operator-edit-cursor edit)
                               operator
                               linewise-p))

  (defun %vi-delete-current (state count)
    (let* ((buffer (input-state-buffer state))
           (position (input-state-cursor-pos state))
           (line-end (%vi-line-end buffer position))
           (end (min line-end (%vi-counted-next-position buffer position count))))
      (if (= position end)
          (values state :none)
          (multiple-value-bind (new-state output)
              (%vi-kill-into state position end position :vi-command)
            (values (%vi-session-with new-state :yank-type :characterwise)
                    output)))))

  (defun %vi-replace-pending (state replacement)
    (let* ((buffer (input-state-buffer state))
           (position (input-state-cursor-pos state))
           (line-end (%vi-line-end buffer position))
           (count (%vi-count state))
           (end (min line-end
                     (%vi-counted-next-position buffer position count)))
           (replaced-count (loop with cursor = position
                                 while (< cursor end)
                                 count t
                                 do (setf cursor (%vi-next-position buffer cursor))))
           (new-buffer (if (zerop replaced-count)
                           buffer
                           (concatenate 'string
                                        (subseq buffer 0 position)
                                        (make-string replaced-count
                                                     :initial-element replacement)
                                        (subseq buffer end)))))
      (values (%vi-command-state
               (copy-input-state-clearing-completion state
                                                     :buffer new-buffer
                                                     :cursor-pos position)
               :cursor-pos position)
              (if (zerop replaced-count) :none :redraw))))

  (defun %vi-put (state after-p)
    (let* ((ring (input-state-kill-ring state))
           (text (first ring)))
      (unless (and (stringp text) (plusp (length text)))
        (return-from %vi-put (values (%vi-command-state state) :none)))
      (let* ((buffer (input-state-buffer state))
             (position (input-state-cursor-pos state))
             (linewise-p (eq (%vi-session-value state :yank-type)
                             :linewise))
             (count (%vi-count state))
             (payload (apply #'concatenate
                             'string
                             (loop repeat count collect text)))
             (insert-position
               (if linewise-p
                   (if after-p
                       (let ((line-end (%vi-line-end buffer position)))
                         (if (< line-end (length buffer))
                             (1+ line-end)
                             line-end))
                       (%vi-line-start buffer position))
                   (if after-p (%vi-next-position buffer position) position)))
             (payload (if (and linewise-p after-p
                               (= insert-position (length buffer))
                               (plusp (length buffer))
                               (not (char= (char buffer (1- (length buffer)))
                                           #\Newline)))
                          (concatenate 'string (string #\Newline) payload)
                          payload))
             (insertion (buffer-insertion-at-cursor buffer
                                                    insert-position
                                                    payload)))
        (if (null insertion)
            (values (%vi-command-state state) :none)
            (let* ((new-buffer (buffer-insertion-result insertion buffer))
                   (inserted-end (buffer-insertion-cursor-pos insertion))
                   (cursor (if linewise-p
                               (if (and after-p
                                        (= insert-position (length buffer))
                                        (plusp (length buffer))
                                        (not (char= (char buffer
                                                         (1- (length buffer)))
                                                    #\Newline)))
                                   (1+ insert-position)
                                   insert-position)
                               (%vi-previous-position new-buffer inserted-end))))
              (values (%vi-command-state
                       (copy-input-state-clearing-completion
                        state
                        :buffer new-buffer
                        :cursor-pos cursor)
                       :cursor-pos cursor)
                      :redraw))))))

  (defun %vi-undo (state)
    (let* ((session (input-state-vi-session state))
           (undo-stack (getf session :undo-stack)))
      (if (null undo-stack)
          (values (%vi-command-state state) :none)
          (let* ((snapshot (first undo-stack))
                 (new-session (%vi-session-plist-with
                  state
                  :undo-stack (rest undo-stack)
                  :redo-stack (cons (%vi-snapshot state)
                                    (getf session :redo-stack))))
                 (restored (%vi-restore-snapshot state snapshot)))
            (values (copy-input-state-with restored
                                           :vi-session new-session
                                           :mode :vi-command
                                           :vi-count nil
                                           :vi-visual-anchor :clear)
                    :redraw)))))

  (defun %vi-redo (state)
    (let* ((session (input-state-vi-session state))
           (redo-stack (getf session :redo-stack)))
      (if (null redo-stack)
          (values (%vi-command-state state) :none)
          (let* ((snapshot (first redo-stack))
                 (new-session (%vi-session-plist-with
                  state
                  :redo-stack (rest redo-stack)
                  :undo-stack (cons (%vi-snapshot state)
                                    (getf session :undo-stack))))
                 (restored (%vi-restore-snapshot state snapshot)))
            (values (copy-input-state-with restored
                                           :vi-session new-session
                                           :mode :vi-command
                                           :vi-count nil
                                           :vi-visual-anchor :clear)
                    :redraw)))))

  (defun %vi-repeat-change (state count)
    (let ((events (%vi-session-value state :last-change)))
      (if (null events)
          (values (%vi-command-state state) :none)
          (let ((origin (%vi-snapshot state))
                (new-state state)
                (*vi-replaying-change-p* t))
            (dotimes (_ count)
              (dolist (event events)
                (multiple-value-bind (next-state output)
                    (reduce-input-state new-state event)
                  (declare (ignore output))
                  (setf new-state next-state))))
            (let ((session (%vi-session-plist-with
                   new-state
                   :undo-stack (cons origin
                                     (%vi-session-value state :undo-stack))
                   :redo-stack nil
                   :pending nil
                   :operator nil
                   :recording-change nil
                   :change-origin nil)))
              (values (copy-input-state-with new-state
                                             :mode :vi-command
                                             :vi-count nil
                                             :vi-visual-anchor :clear
                                             :vi-session session)
                      :redraw))))))

  (defun %vi-common-motion (state ch count)
    (let* ((buffer (input-state-buffer state))
           (position (input-state-cursor-pos state))
           (line-start (%vi-line-start buffer position))
           (line-end (%vi-line-end buffer position))
           (target
             (case ch
               (#\h (max line-start
                         (%vi-counted-previous-position buffer position count)))
               (#\l (min (%vi-previous-position buffer line-end)
                         (%vi-counted-next-position buffer position count)))
               (#\0 line-start)
               (#\^ (or (position-if-not
                         (lambda (character)
                           (member character (list #\Space #\Tab #\Return)))
                         buffer
                         :start line-start
                         :end line-end)
                        line-start))
               (#\$ (if (> line-end line-start)
                        (%vi-previous-position buffer line-end)
                        line-start))
               (#\w (let ((moved (%vi-counted-word-right state count)))
                      (%vi-grapheme-floor
                       buffer (input-state-cursor-pos moved))))
               (#\b (let ((moved (%vi-counted-word-left state count)))
                      (%vi-grapheme-floor
                       buffer (input-state-cursor-pos moved))))
               (#\e (%vi-counted-word-end-position buffer position count)))))
      (if target
          (values (%vi-command-state state :cursor-pos
                                     (max 0 (min (%vi-last-column state)
                                                 target)))
                  :redraw
                  t)
          (values state :none nil))))

  (defun %vi-begin-find (state ch)
    (%vi-set-pending state :find :motion ch))

  (defun %vi-operator-mode-p (state)
    (member (input-state-mode state) '(:vi-d :vi-c) :test #'eq))

  (defun %vi-pending-find (state target-character)
    (let* ((motion (%vi-pending-value state :motion))
           (count (%vi-count state))
           (target (%vi-find-target state motion target-character count))
           (remembered (%vi-session-with state
                                         :last-find (list motion target-character))))
      (if (null target)
          (values (%vi-command-state state) :none)
          (if (%vi-operator-mode-p state)
              (let* ((operator (%vi-operator state))
                     (edit (%vi-find-operator-edit remembered motion target))
                     (linewise-p nil))
                (%vi-apply-operator-edit remembered edit operator linewise-p))
              (values (%vi-command-state remembered :cursor-pos target)
                      :redraw)))))

  (defun %vi-repeat-find (state reverse-p)
    (let* ((last-find (%vi-session-value state :last-find))
           (motion (and last-find
                        (%vi-find-motion-type (first last-find) reverse-p)))
           (target-character (second last-find)))
      (if (null motion)
          (values (%vi-command-state state) :none)
          (let ((target (%vi-find-target state motion target-character
                                         (%vi-count state))))
            (if (null target)
                (values (%vi-command-state state) :none)
                (if (%vi-operator-mode-p state)
                    (%vi-apply-operator-edit
                     state
                     (%vi-find-operator-edit state motion target)
                     (%vi-operator state)
                     nil)
                    (values (%vi-command-state state :cursor-pos target)
                            :redraw)))))))

  (defun %vi-pending-text-object (state object-character)
    (multiple-value-bind (start end)
        (%vi-text-object-range state
                               object-character
                               (%vi-pending-value state :around))
      (if (or (null start) (null end))
          (values (%vi-command-state state) :none)
          (%vi-apply-operator-edit
           state
           (%make-vi-operator-edit
            start end start
            (if (eq (%vi-operator state) :c) :insert :vi-command))
           (%vi-operator state)
           nil))))

  (defun %vi-pending-command (state ch)
    (case (%vi-pending-kind state)
      (:g
       (if (char= ch #\g)
           (let* ((line (%vi-count state))
                  (target (%vi-counted-line-position state line)))
             (if (%vi-operator-mode-p state)
                 (%vi-apply-operator-edit
                  state
                  (%make-vi-operator-edit
                   0 (input-state-cursor-pos state) 0
                   (if (eq (%vi-operator state) :c) :insert :vi-command))
                  (%vi-operator state)
                  nil)
                 (values (%vi-command-state state :cursor-pos target)
                         :redraw)))
           (values (%vi-command-state state) :redraw)))
      (:find (%vi-pending-find state ch))
      (:replace (%vi-replace-pending state ch))
      (:text-object (%vi-pending-text-object state ch))
      (otherwise (values (%vi-command-state state) :redraw))))

  (defun %vi-reduce-operator (state ch)
    (let ((operator (%vi-operator state)))
      (cond
        ((member ch '(#\f #\F #\t #\T))
         (values (%vi-begin-find state ch) :redraw))
        ((char= ch #\g)
         (values (%vi-set-pending state :g) :redraw))
        ((char= ch #\i)
         (values (%vi-set-pending state :text-object :around nil) :redraw))
        ((char= ch #\a)
         (values (%vi-set-pending state :text-object :around t) :redraw))
        ((member ch '(#\; #\,))
         (%vi-repeat-find state (char= ch #\,)))
        (t
         (let ((edit (vi-operator-edit-for-motion state ch operator)))
           (if edit
               (%vi-apply-operator-edit
                state edit operator (char= ch (ecase operator
                                                (:d #\d)
                                                (:c #\c)
                                                (:y #\y))))
               (values (%vi-command-state state) :redraw)))))))

  (defun %vi-reduce-normal (state ch)
    (let* ((position (input-state-cursor-pos state))
           (length (%vi-buffer-length state))
           (count (%vi-count state)))
      (cond
        ((and (digit-char-p ch)
              (or (not (char= ch #\0))
                  (input-state-vi-count state)))
         (values (%vi-accumulate-count state ch) :redraw))
        ((member ch (list #\h #\l #\0 #\^ #\$ #\w #\b #\e))
         (multiple-value-bind (new-state output handled-p)
             (%vi-common-motion state ch count)
           (declare (ignore handled-p))
           (values new-state output)))
        ((member ch (list #\f #\F #\t #\T))
         (values (%vi-begin-find state ch) :redraw))
        ((char= ch #\;) (%vi-repeat-find state nil))
        ((char= ch #\,) (%vi-repeat-find state t))
        ((char= ch #\g)
         (values (%vi-set-pending state :g) :redraw))
        ((char= ch #\G)
         (let ((target (if (input-state-vi-count state)
                           (%vi-counted-line-position state count)
                           (%vi-last-column state))))
           (values (%vi-command-state state :cursor-pos target) :redraw)))
        ((char= ch #\u) (%vi-undo state))
        ((char= ch #\.) (%vi-repeat-change state count))
        ((char= ch #\r)
         (values (%vi-set-pending state :replace) :redraw))
        ((char= ch #\v) (values (%vi-enter-visual state) :redraw))
        ((char= ch #\i) (values (%vi-enter-insert state) :redraw))
        ((char= ch #\a)
         (values (%vi-enter-insert state
                                   (min length (%vi-next-position
                                                (input-state-buffer state)
                                                position)))
                 :redraw))
        ((char= ch #\I)
         (values (%vi-enter-insert
                  state
                  (%vi-line-start (input-state-buffer state) position))
                 :redraw))
        ((char= ch #\A)
         (values (%vi-enter-insert
                  state
                  (%vi-line-end (input-state-buffer state) position))
                 :redraw))
        ((char= ch #\x) (%vi-delete-current state count))
        ((char= ch #\D)
         (let* ((buffer (input-state-buffer state))
                (line-end (%vi-line-end buffer position))
                (range-length (- line-end position)))
           (%vi-delete-current state (max 1 range-length))))
        ((char= ch #\C)
         (%vi-commit-operator-range
          state position
          (%vi-line-end (input-state-buffer state) position)
          position :c nil))
        ((char= ch #\s)
         (let* ((buffer (input-state-buffer state))
                (line-end (%vi-line-end buffer position))
                (end (min line-end
                          (%vi-counted-next-position buffer position count))))
           (%vi-commit-operator-range state position end position :c nil)))
        ((char= ch #\d) (values (%vi-start-operator state :d) :redraw))
        ((char= ch #\c) (values (%vi-start-operator state :c) :redraw))
        ((char= ch #\y) (values (%vi-start-operator state :y) :redraw))
        ((char= ch #\p) (%vi-put state t))
        ((char= ch #\P) (%vi-put state nil))
        ((char= ch #\j) (%vi-values-clearing-count state :history-next))
        ((char= ch #\k) (%vi-values-clearing-count state :history-prev))
        (t (values state :none)))))

  (defun %vi-reduce-visual (state ch)
    (let ((position (input-state-cursor-pos state))
          (count (%vi-count state))
          (buffer (input-state-buffer state)))
      (multiple-value-bind (motion-state output handled-p)
          (%vi-common-motion state ch count)
        (when handled-p
          (return-from %vi-reduce-visual
            (values (copy-input-state-with motion-state
                                           :mode :vi-visual
                                           :vi-visual-anchor
                                           (input-state-vi-visual-anchor state))
                    output))))
      (case ch
        (#\v (values (%vi-command-state state) :redraw))
        (#\o (%vi-swap-visual-anchor state))
        ((#\d #\x)
         (multiple-value-bind (start end) (%vi-visual-range state)
           (%vi-commit-operator-range state start end start :d nil)))
        (#\c
         (multiple-value-bind (start end) (%vi-visual-range state)
           (%vi-commit-operator-range state start end start :c nil)))
        (#\y
         (multiple-value-bind (start end) (%vi-visual-range state)
           (%vi-commit-operator-range state start end start :y nil)))
        (#\i (values (%vi-enter-insert (%vi-leave-visual state)) :redraw))
        (#\a (values (%vi-enter-insert
                      (%vi-leave-visual state)
                      (min (length buffer)
                           (%vi-next-position buffer position)))
                     :redraw))
        (t (values state :none)))))

  (defun reduce-vi-input-state (state key-event)
    (let ((type (nshell.domain.input:key-event-type key-event))
          (mode (input-state-mode state)))
      (case type
        (:ctrl-right-bracket (%start-ask-input-state state))
        (:enter (finalize-enter-input-state (%vi-insert-state state)))
        (:ctrl-c (clear-input-state state))
        (:ctrl-l (%vi-values-clearing-count state :clear-screen))
        (:ctrl-r (%vi-redo state))
        ((:up) (%vi-values-clearing-count state :history-prev))
        ((:down) (%vi-values-clearing-count state :history-next))
        ((:left)
         (%vi-values-clearing-count
          (%vi-command-state state
                             :cursor-pos
                             (%vi-previous-position
                              (input-state-buffer state)
                              (input-state-cursor-pos state)))
          :redraw))
        ((:right)
         (%vi-values-clearing-count
          (%vi-command-state state
                             :cursor-pos
                             (min (%vi-last-column state)
                                  (%vi-next-position
                                   (input-state-buffer state)
                                   (input-state-cursor-pos state))))
          :redraw))
        (:char
         (let ((ch (nshell.domain.input:key-event-char key-event)))
           (cond
             ((null ch) (values state :none))
             ((%vi-pending-kind state) (%vi-pending-command state ch))
             ((%vi-operator-mode-p state) (%vi-reduce-operator state ch))
             ((eq mode :vi-visual)
             (if (and (digit-char-p ch)
                      (or (not (char= ch #\0))
                          (input-state-vi-count state)))
                 (values (%vi-accumulate-count state ch) :redraw)
                 (%vi-reduce-visual state ch)))
             (t (%vi-reduce-normal state ch)))))
        (:escape (values (%vi-command-state state) :redraw))
        (otherwise (values state :none)))))

  (defun %vi-change-starter-p (state key-event)
    (and (eq (input-state-mode state) :vi-command)
         (eq (nshell.domain.input:key-event-type key-event) :char)
         (member (nshell.domain.input:key-event-char key-event)
                 '(#\d #\c #\x #\D #\C #\s #\p #\P #\r #\i #\a #\I #\A)
                 :test #'char=)))

  (defun %vi-recording-complete-p (state output)
    (or (eq output :execute)
        (and (eq (input-state-mode state) :vi-command)
             (null (%vi-pending-kind state)))))

  (defun record-vi-input-transition (old-state new-state key-event output)
    (if *vi-replaying-change-p*
        new-state
        (let* ((type (nshell.domain.input:key-event-type key-event))
               (character (and (eq type :char)
                               (nshell.domain.input:key-event-char key-event)))
               (old-recording (%vi-session-value old-state :recording-change))
               (count-events (%vi-session-value old-state :count-events)))
          (cond
            ((and (null old-recording)
                  (eq (input-state-mode old-state) :vi-command)
                  character
                  (digit-char-p character)
                  (input-state-vi-count new-state))
             (%vi-session-with
              new-state
              :count-events (append count-events (list key-event))))
            ((and (null old-recording)
                  (%vi-change-starter-p old-state key-event))
             (let* ((events (append count-events (list key-event)))
                    (origin (%vi-snapshot old-state))
                    (state (%vi-session-with
                            new-state
                            :count-events nil
                            :recording-change events
                            :change-origin origin)))
               (if (%vi-recording-complete-p state output)
                   (%vi-finish-recorded-change state)
                   state)))
            (old-recording
             (let* ((events (append old-recording (list key-event)))
                    (state (%vi-session-with new-state
                                             :recording-change events)))
               (cond
                 ((eq output :execute)
                  (%vi-session-with state
                                    :recording-change nil
                                    :change-origin nil
                                    :count-events nil))
                 ((%vi-recording-complete-p state output)
                  (%vi-finish-recorded-change state))
                 (t state))))
            (t (%vi-session-with new-state :count-events nil))))))

  (defun %vi-finish-recorded-change (state)
    (let* ((origin (%vi-session-value state :change-origin))
           (recording (%vi-session-value state :recording-change))
           (changed (and origin
                         (not (string= (getf origin :buffer)
                                       (input-state-buffer state)))))
           (session (if changed
                        (%vi-session-with
                         state
                         :undo-stack
                         (cons origin
                               (%vi-session-value state :undo-stack))
                         :redo-stack nil
                         :last-change recording)
                        (%vi-session-with state :recording-change nil
                                          :change-origin nil
                                          :count-events nil))))
      (if changed
          (%vi-session-with session
                            :recording-change nil
                            :change-origin nil
                            :count-events nil)
          session)))

)
