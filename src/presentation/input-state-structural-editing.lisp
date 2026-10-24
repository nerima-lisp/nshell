(in-package #:nshell.presentation)

(defstruct
    (%sexp-structural-expression
     (:constructor %make-sexp-structural-expression
                   (start end
                          kind
                          &optional
                          open-start
                          open-end
                          close-start
                          close-end)))
  start
  end
  kind
  open-start
  open-end
  close-start
  close-end)

(defun %sexp-token-start (token)
  (first (nshell.domain.parsing:scan-token-span token)))

(defun %sexp-token-end (token)
  (second (nshell.domain.parsing:scan-token-span token)))

(defun %sexp-token-at-position (tokens position)
  (find-if
   (lambda (token)
     (let ((span (nshell.domain.parsing:scan-token-span token)))
       (and (<= (first span) position) (< position (second span)))))
   tokens))

(defun %sexp-token-at-start (tokens position kind)
  (find-if
   (lambda (token)
     (and (= position (%sexp-token-start token))
          (eq kind (nshell.domain.parsing:scan-token-kind token))))
   tokens))

(defun %sexp-token-trivia-p (token)
  (member (nshell.domain.parsing:scan-token-kind token)
          '(:whitespace :line-comment :block-comment)
          :test
          #'eq))

(defun %sexp-reader-prefix-token-p (token)
  (member (nshell.domain.parsing:scan-token-kind token)
          '(:reader-prefix :comma-unquote :dollar-unquote)
          :test
          #'eq))

(defun %sexp-reader-prefix-start (tokens start)
  (let ((position start)
        (prefix-start start))
    (dolist (token (reverse tokens) prefix-start)
      (let ((token-start (%sexp-token-start token))
            (token-end (%sexp-token-end token)))
        (when (< token-start position)
          (cond
            ((%sexp-token-trivia-p token)
             (setf position token-start))
            ((and (<= token-end position)
                  (eq :host-form
                      (nshell.domain.parsing:scan-token-reader-context token))
                  (%sexp-reader-prefix-token-p token))
             (setf position token-start
                   prefix-start token-start))
            (t (return prefix-start))))))))

(defun %sexp-delimiter-close-token (tokens pair)
  (%sexp-token-at-start tokens
                        (first
                         (nshell.domain.parsing:delimiter-pair-close-span pair))
                        :delimiter-close))

(defun %sexp-structural-expressions (scan-result)
  (let ((tokens (nshell.domain.parsing:scan-result-tokens scan-result))
        (expressions nil))
    (dolist
        (pair (nshell.domain.parsing:scan-result-delimiter-pairs scan-result))
      (let* ((open-span (nshell.domain.parsing:delimiter-pair-open-span pair))
             (close-span (nshell.domain.parsing:delimiter-pair-close-span pair))
             (close-token (%sexp-delimiter-close-token tokens pair)))
        (when close-token
          (let* ((kind
                  (if (eq :host-form
                          (nshell.domain.parsing:scan-token-reader-context
                           close-token))
                      :list
                      :island))
                 (open-start (first open-span))
                 (open-end (second open-span))
                 (close-start (first close-span))
                 (close-end (second close-span)))
            (push
             (%make-sexp-structural-expression
              (%sexp-reader-prefix-start tokens open-start)
              close-end
              kind
              open-start
              open-end
              close-start
              close-end)
             expressions)))))
    (dolist (token tokens)
      (when
          (and
           (eq :host-form
               (nshell.domain.parsing:scan-token-reader-context token))
           (member (nshell.domain.parsing:scan-token-kind token)
                   '(:host-form :string :escaped-symbol :character-literal)
                   :test
                   #'eq))
        (push
         (%make-sexp-structural-expression
          (%sexp-reader-prefix-start tokens (%sexp-token-start token))
          (%sexp-token-end token)
          :atom)
         expressions)))
    (stable-sort expressions #'< :key #'%sexp-structural-expression-start)))

(defun %sexp-expression-contains-span-p (outer inner)
  (and
   (<= (%sexp-structural-expression-start outer)
       (%sexp-structural-expression-start inner))
   (<= (%sexp-structural-expression-end inner)
       (%sexp-structural-expression-end outer))
   (or
    (< (%sexp-structural-expression-start outer)
       (%sexp-structural-expression-start inner))
    (> (%sexp-structural-expression-end outer)
       (%sexp-structural-expression-end inner)))))

(defun %sexp-expression-span-length (expression)
  (- (%sexp-structural-expression-end expression)
     (%sexp-structural-expression-start expression)))

(defun %sexp-smallest-expression-containing (expressions position direction)
  (let ((matches
         (remove-if-not
          (lambda (expression)
            (let ((start (%sexp-structural-expression-start expression))
                  (end (%sexp-structural-expression-end expression)))
              (if (eq direction :forward)
                  (and (<= start position) (< position end))
                  (and (< start position) (<= position end)))))
          expressions)))
    (car (stable-sort matches #'< :key #'%sexp-expression-span-length))))

(defun %sexp-expressions-contained-in (expressions start end)
  (let ((contained
         (remove-if-not
          (lambda (expression)
            (and (<= start (%sexp-structural-expression-start expression))
                 (<= (%sexp-structural-expression-end expression) end)))
          expressions)))
    (stable-sort
     (remove-if
      (lambda (expression)
        (some
         (lambda (container)
           (%sexp-expression-contains-span-p container expression))
         contained))
      contained)
     #'<
     :key
     #'%sexp-structural-expression-start)))

(defun %sexp-list-children (expressions list-expression)
  (%sexp-expressions-contained-in expressions
                                  (%sexp-structural-expression-open-end
                                   list-expression)
                                  (%sexp-structural-expression-close-start
                                   list-expression)))

(defun %sexp-root-expressions (expressions)
  (stable-sort
   (remove-if
    (lambda (expression)
      (some
       (lambda (container)
         (%sexp-expression-contains-span-p container expression))
       expressions))
    (copy-list expressions))
   #'<
   :key
   #'%sexp-structural-expression-start))

(defun %sexp-innermost-list-containing (expressions position)
  (let ((matches
         (remove-if-not
          (lambda (expression)
            (and (eq :list (%sexp-structural-expression-kind expression))
                 (<= (%sexp-structural-expression-open-end expression) position)
                 (<= position
                     (%sexp-structural-expression-close-start expression))))
          expressions)))
    (car (stable-sort matches #'< :key #'%sexp-expression-span-length))))

(defun %sexp-parent-list (expressions expression)
  (let ((matches
         (remove-if-not
          (lambda (candidate)
            (and (eq :list (%sexp-structural-expression-kind candidate))
                 (%sexp-expression-contains-span-p candidate expression)))
          expressions)))
    (car (stable-sort matches #'< :key #'%sexp-expression-span-length))))

(defun %sexp-expression-siblings (expressions expression)
  (let ((parent (%sexp-parent-list expressions expression)))
    (if parent
        (%sexp-list-children expressions parent)
        (%sexp-root-expressions expressions))))

(defun %sexp-command-island-position-p (expressions position)
  (some
   (lambda (expression)
     (and (eq :island (%sexp-structural-expression-kind expression))
          (<= (%sexp-structural-expression-open-end expression) position)
          (< position (%sexp-structural-expression-close-end expression))))
   expressions))

(defun %sexp-list-at-delimiter-token (expressions token)
  (let ((position (%sexp-token-start token))
        (kind (nshell.domain.parsing:scan-token-kind token)))
    (find-if
     (lambda (expression)
       (and (eq :list (%sexp-structural-expression-kind expression))
            (if (eq kind :delimiter-open)
                (= position (%sexp-structural-expression-open-start expression))
                (= position
                   (%sexp-structural-expression-close-start expression)))))
     expressions)))

(defun %sexp-expression-at-token (expressions token position direction)
  (let ((kind (nshell.domain.parsing:scan-token-kind token)))
    (cond
      ((eq kind :delimiter-open)
       (when (eq direction :forward)
         (%sexp-list-at-delimiter-token expressions token)))
      ((eq kind :delimiter-close)
       (%sexp-list-at-delimiter-token expressions token))
      ((%sexp-token-trivia-p token) nil)
      (t
       (%sexp-smallest-expression-containing
        (remove-if
         (lambda (expression)
           (eq :island (%sexp-structural-expression-kind expression)))
         expressions)
        position
        direction)))))

(defun %sexp-trivia-neighbor (expressions tokens
                                          position
                                          direction
                                          &key
                                          container-fallback-p)
  (let* ((container (%sexp-innermost-list-containing expressions position))
         (siblings
          (if container
              (%sexp-list-children expressions container)
              (%sexp-root-expressions expressions)))
         (neighbor
          (if (eq direction :forward)
              (find-if
               (lambda (expression)
                 (>= (%sexp-structural-expression-start expression) position))
               siblings)
              (car
               (last
                (remove-if-not
                 (lambda (expression)
                   (<= (%sexp-structural-expression-end expression) position))
                 siblings))))))
    (declare (ignore tokens))
    (or neighbor (and container-fallback-p container))))

(defun %sexp-select-expression (expressions tokens
                                            position
                                            direction
                                            &key
                                            container-fallback-p)
  (or
   (let ((token (%sexp-token-at-position tokens position)))
     (and token
          (%sexp-expression-at-token expressions token position direction)))
   (%sexp-trivia-neighbor expressions
                          tokens
                          position
                          direction
                          :container-fallback-p
                          container-fallback-p)))

(defun %sexp-change-cursor (state position)
  (if (= position (input-state-cursor-pos state))
      (values state :none)
      (values (copy-input-state-clearing-completion state :cursor-pos position)
              :redraw)))

(defun %sexp-change-buffer (state buffer cursor)
  (if (string= buffer (input-state-buffer state))
      (values state :none)
      (values
       (copy-input-state-clearing-completion state
                                             :buffer
                                             buffer
                                             :cursor-pos
                                             cursor)
       :suggest-update)))

(defun %sexp-move-delimiter (buffer from to delimiter cursor)
  (let* ((without-delimiter
          (concatenate 'string (subseq buffer 0 from) (subseq buffer (1+ from))))
         (insert-position
          (if (> to from)
              (1- to)
              to))
         (new-buffer
          (concatenate 'string
                       (subseq without-delimiter 0 insert-position)
                       (string delimiter)
                       (subseq without-delimiter insert-position)))
         (cursor-after-delete
          (if (> cursor from)
              (1- cursor)
              cursor))
         (new-cursor
          (if (<= insert-position cursor-after-delete)
              (1+ cursor-after-delete)
              cursor-after-delete)))
    (values new-buffer new-cursor)))

(defun %sexp-move-list-delimiter (state list-expression to delimiter)
  (multiple-value-bind (buffer cursor)
      (%sexp-move-delimiter (input-state-buffer state)
                            (if (char= delimiter #\()
                                (%sexp-structural-expression-open-start
                                 list-expression)
                                (%sexp-structural-expression-close-start
                                 list-expression))
                            to
                            delimiter
                            (input-state-cursor-pos state))
    (%sexp-change-buffer state buffer cursor)))

(defun %sexp-sibling-after (expressions expression)
  (let* ((siblings (%sexp-expression-siblings expressions expression))
         (position (position expression siblings :test #'eq)))
    (and position (nth (1+ position) siblings))))

(defun %sexp-sibling-before (expressions expression)
  (let* ((siblings (%sexp-expression-siblings expressions expression))
         (position (position expression siblings :test #'eq)))
    (and position (plusp position) (nth (1- position) siblings))))

(defun %sexp-current-list (expressions tokens position)
  (let* ((token (%sexp-token-at-position tokens position))
         (from-delimiter
          (and token
               (member (nshell.domain.parsing:scan-token-kind token)
                       '(:delimiter-open :delimiter-close)
                       :test
                       #'eq)
               (%sexp-list-at-delimiter-token expressions token))))
    (or from-delimiter (%sexp-innermost-list-containing expressions position))))

(defun %sexp-slurp (state expressions tokens direction)
  (let* ((position (input-state-cursor-pos state))
         (list-expression (%sexp-current-list expressions tokens position))
         (sibling
          (and list-expression
               (if (eq direction :forward)
                   (%sexp-sibling-after expressions list-expression)
                   (%sexp-sibling-before expressions list-expression)))))
    (if (null sibling)
        (values state :none)
        (%sexp-move-list-delimiter state
                                   list-expression
                                   (if (eq direction :forward)
                                       (%sexp-structural-expression-end sibling)
                                       (%sexp-structural-expression-start
                                        sibling))
                                   (if (eq direction :forward)
                                       #\)
                                       #\()))))

(defun %sexp-barf (state expressions tokens direction)
  (let* ((position (input-state-cursor-pos state))
         (list-expression (%sexp-current-list expressions tokens position))
         (children
          (and list-expression
               (%sexp-list-children expressions list-expression))))
    (if (or (null list-expression) (null children))
        (values state :none)
        (let* ((destination
                (if (eq direction :forward)
                    (if (rest children)
                        (%sexp-structural-expression-end
                         (first (last children 2)))
                        (%sexp-structural-expression-open-end list-expression))
                    (if (rest children)
                        (%sexp-structural-expression-start (second children))
                        (%sexp-structural-expression-close-start
                         list-expression))))
               (delimiter
                (if (eq direction :forward)
                    #\)
                    #\()))
          (%sexp-move-list-delimiter state
                                     list-expression
                                     destination
                                     delimiter)))))

(defun %sexp-navigation-action (state expressions tokens action)
  (let* ((position (input-state-cursor-pos state))
         (target
          (case action
            (:forward-sexp
             (%sexp-select-expression expressions
                                      tokens
                                      position
                                      :forward
                                      :container-fallback-p
                                      t))
            (:backward-sexp
             (%sexp-select-expression expressions
                                      tokens
                                      position
                                      :backward
                                      :container-fallback-p
                                      t))
            (:up-list (%sexp-innermost-list-containing expressions position))
            (:down-list
             (car
              (stable-sort
               (remove-if-not
                (lambda (expression)
                  (and (eq :list (%sexp-structural-expression-kind expression))
                       (>= (%sexp-structural-expression-open-start expression)
                           position)
                       (not
                        (%sexp-command-island-position-p expressions
                                                         (%sexp-structural-expression-open-start
                                                          expression)))))
                (copy-list expressions))
               #'<
               :key
               #'%sexp-structural-expression-open-start))))))
    (if target
        (%sexp-change-cursor state
                             (case action
                               ((:forward-sexp :down-list)
                                (if (eq action :down-list)
                                    (%sexp-structural-expression-open-end
                                     target)
                                    (%sexp-structural-expression-end target)))
                               ((:backward-sexp :up-list)
                                (if (eq action :up-list)
                                    (%sexp-structural-expression-close-end
                                     target)
                                    (%sexp-structural-expression-start target)))))
        (values state :none))))

(defun %sexp-delete-action (state expressions tokens direction)
  (let* ((position (input-state-cursor-pos state))
         (expression
          (%sexp-select-expression expressions tokens position direction)))
    (if expression
        (%kill-range state
                     (%sexp-structural-expression-start expression)
                     (%sexp-structural-expression-end expression)
                     (%sexp-structural-expression-start expression))
        (values state :none))))

(defun apply-sexp-structural-edit (state scan-result action)
  (if (not
       (eq :complete (nshell.domain.parsing:scan-result-status scan-result)))
      (values state :none)
      (let* ((expressions (%sexp-structural-expressions scan-result))
             (tokens (nshell.domain.parsing:scan-result-tokens scan-result))
             (position (input-state-cursor-pos state)))
        (if (%sexp-command-island-position-p expressions position)
            (values state :none)
            (case action
              ((:forward-sexp :backward-sexp :up-list :down-list)
               (%sexp-navigation-action state expressions tokens action))
              (:delete-forward-sexp
               (%sexp-delete-action state expressions tokens :forward))
              (:delete-backward-sexp
               (%sexp-delete-action state expressions tokens :backward))
              (:slurp-forward (%sexp-slurp state expressions tokens :forward))
              (:slurp-backward (%sexp-slurp state expressions tokens :backward))
              (:barf-forward (%sexp-barf state expressions tokens :forward))
              (:barf-backward (%sexp-barf state expressions tokens :backward))
              (otherwise (values state :none)))))))

(defun %reduce-sexp-structural-edit (state action)
  (let* ((state (normalize-input-state state))
         (context (%make-repl-shell-context))
         (scan-result
          (%repl-input-scan-result (input-state-buffer state)
                                   (input-state-cursor-pos state)
                                   :sexp
                                   :head-classifier
                                   (%repl-completion-head-classifier context))))
    (apply-sexp-structural-edit state scan-result action)))
