;;; Completion cycling helpers for the input reducer.

(in-package #:nshell.presentation)

(define-value-struct %completion-cycle-selection
    ((base-buffer "" :type string)
     (base-cursor 0 :type fixnum)
     (index 0 :type fixnum)
     (candidate "")))

(defun completion-cycle-selection-for-state (state direction candidates)
  (let* ((count (length candidates))
         (first-cycle-p (= -1 (input-state-completion-index state)))
         (base-buffer (if first-cycle-p
                          (input-state-buffer state)
                          (or (input-state-completion-base-buffer state)
                              (input-state-buffer state))))
         (base-cursor (if first-cycle-p
                          (input-state-cursor-pos state)
                          (or (input-state-completion-base-cursor state)
                              (length base-buffer))))
          (index (if first-cycle-p
                     (if (minusp direction)
                         (1- count)
                         0)
                     (mod (+ (input-state-completion-index state) direction)
                          count))))
    (%make-completion-cycle-selection
     base-buffer
     base-cursor
     index
     (nth index candidates))))

(define-value-struct %completion-cycle-edit
    ((base-buffer "" :type string)
     (base-cursor 0 :type fixnum)
     (index 0 :type fixnum)
     (buffer "" :type string)
     (cursor-pos 0 :type fixnum)))

(defun completion-cycle-edit-for-selection (selection)
  (let ((base-buffer (completion-cycle-selection-base-buffer selection))
        (base-cursor (completion-cycle-selection-base-cursor selection)))
    (multiple-value-bind (buffer cursor)
        (apply-completion base-buffer
                          (completion-cycle-selection-candidate selection)
                          :cursor base-cursor)
      (%make-completion-cycle-edit
       base-buffer
       base-cursor
       (completion-cycle-selection-index selection)
       buffer
       cursor))))

(defun commit-completion-cycle-edit (state edit)
  (copy-input-state-with state
                         :suggestion :clear
                         :buffer (completion-cycle-edit-buffer edit)
                         :cursor-pos (completion-cycle-edit-cursor-pos edit)
                         :completion-index (completion-cycle-edit-index edit)
                         :completion-base-buffer
                         (completion-cycle-edit-base-buffer edit)
                         :completion-base-cursor
                         (completion-cycle-edit-base-cursor edit)))

(defun cycle-completion-state (state direction)
  (with-normalized-input-state (state state)
    (let ((candidates (input-state-last-candidates state)))
      (if (null candidates)
          (values state :complete)
          (let ((selection (completion-cycle-selection-for-state
                            state
                            direction
                            candidates)))
            (values (commit-completion-cycle-edit
                     state
                     (completion-cycle-edit-for-selection selection))
                    :complete))))))
(defun completion-pager-filtered-candidates (state)
  (let ((query (getf (input-state-completion-pager state) :query "")))
    (remove-if-not
     (lambda (candidate)
       (or (string= query "")
           (search query (%candidate-text candidate) :test #'char-equal)))
     (input-state-last-candidates state))))
(defun reduce-completion-pager-input-state (state key-event)
  (let* ((pager (input-state-completion-pager state))
         (query (getf pager :query ""))
         (selected-index (getf pager :index 0))
         (type (nshell.domain.input:key-event-type key-event)))
    (labels ((update (new-query new-index)
                     (values (copy-input-state-with
                              state
                              :completion-pager
                              (list :query new-query :index new-index))
                             :redraw))
             (move-selection (delta)
                             (let* ((candidates (completion-pager-filtered-candidates state))
                                    (last-index (max 0 (1- (length candidates)))))
                               (update query
                                       (max 0 (min last-index (+ selected-index delta))))))
             (accept-selection ()
                               (let* ((candidates (completion-pager-filtered-candidates state))
                                      (candidate (nth selected-index candidates))
                                      (base-buffer (or (input-state-completion-base-buffer state)
                                                       (input-state-buffer state)))
                                      (base-cursor (or (input-state-completion-base-cursor state)
                                                       (input-state-cursor-pos state))))
                                 (if candidate
                                     (multiple-value-bind (buffer cursor)
                                         (apply-completion base-buffer candidate :cursor base-cursor)
                                       (values (copy-input-state-clearing-completion
                                                state
                                                :buffer buffer
                                                :cursor-pos cursor
                                                :suggestion :clear)
                                               :redraw))
                                   (values state :redraw))))
             (append-query (text) (let ((added (with-output-to-string (out) (loop with remaining = (max 0 (- +max-input-buffer-size+ (length query))) for char across text while (plusp remaining) when (graphic-char-p char) do (write-char char out) (decf remaining))))) (update (concatenate 'string query added) 0))))
      (case type
        (:char
         (let ((char (nshell.domain.input:key-event-char key-event)))
           (if (and char (graphic-char-p char))
               (append-query (string char))
             (values state :none))))
        (:paste
         (let ((text (getf (nshell.domain.input:key-event-data key-event) :text)))
           (if (stringp text)
               (append-query text)
             (values state :none))))
        (:backspace
         (if (plusp (length query))
             (update (subseq query 0 (1- (length query))) 0)
           (values state :redraw)))
        (:up (multiple-value-bind (columns) (%compute-columns (completion-pager-filtered-candidates state)) (move-selection (- columns))))
        (:down (multiple-value-bind (columns) (%compute-columns (completion-pager-filtered-candidates state)) (move-selection columns)))
        (:left (move-selection -1))
        (:right (move-selection 1))
        (:page-up (move-selection -8))
        (:page-down (move-selection 8))
        (:home (update query 0))
        (:end (update query
                      (max 0 (1- (length
                                  (completion-pager-filtered-candidates state))))))
        ((:enter :tab) (accept-selection))
        ((:escape :ctrl-g :ctrl-c)
         (values (clear-completion-session-state state) :redraw))
        (otherwise (values state :none))))))
