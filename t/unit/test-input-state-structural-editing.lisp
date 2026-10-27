(in-package #:nshell/test)

(describe "input-state-structural-editing-tests"
  (it "sexp-navigation-moves-forward-backward-and-between-list-levels"
    (let ((state (input-state :buffer "(list alpha beta)" :cursor-pos 6)))
      (with-reduced-input-state (forward forward-output)
            (reduce-once state :alt-ctrl-f)
          (is-input-state forward :buffer "(list alpha beta)" :cursor-pos 11)
          (expect :redraw :to-be forward-output)
          (with-reduced-input-state (backward backward-output)
              (reduce-once forward :alt-ctrl-b)
            (is-input-state backward :buffer "(list alpha beta)" :cursor-pos 6)
            (expect :redraw :to-be backward-output)))
      (with-reduced-input-state (entered enter-output)
          (reduce-once (input-state :buffer "(list alpha beta)" :cursor-pos 0)
                       :alt-ctrl-d)
        (is-input-state entered :cursor-pos 1)
        (expect :redraw :to-be enter-output)
        (with-reduced-input-state (exited exit-output)
            (reduce-once entered :alt-ctrl-u)
          (is-input-state exited :cursor-pos 17)
          (expect :redraw :to-be exit-output)))))

  (it "sexp-navigation-scans-without-evaluating-reader-forms"
    (let ((marker nil)
          (state (input-state :buffer "(progn (setq marker t))"
                              :cursor-pos 1)))
      (with-reduced-input-state (moved output)
          (reduce-once state :alt-ctrl-f)
        (is-input-state moved :buffer "(progn (setq marker t))" :cursor-pos 6)
        (expect :redraw :to-be output)
        (expect marker :to-be-null))))

  (it "delete-sexp-kills-the-selected-expression-and-yank-restores-it"
    (let ((state (input-state :buffer "alpha beta" :cursor-pos 0)))
      (with-reduced-input-state (deleted delete-output)
          (reduce-once state :alt-ctrl-k)
        (is-input-state deleted
                        :buffer " beta"
                        :cursor-pos 0
                        :kill-ring '("alpha"))
        (expect :suggest-update :to-be delete-output)
        (with-reduced-input-state (yanked yank-output)
            (reduce-once deleted :ctrl-y)
          (is-input-state yanked
                          :buffer "alpha beta"
                          :cursor-pos 5
                          :kill-ring '("alpha"))
          (expect :suggest-update :to-be yank-output)))
      (with-reduced-input-state (deleted delete-output)
          (reduce-once (input-state :buffer "alpha beta" :cursor-pos 5)
                       :alt-ctrl-delete)
        (is-input-state deleted
                        :buffer " beta"
                        :cursor-pos 0
                        :kill-ring '("alpha"))
        (expect :suggest-update :to-be delete-output))))

  (it "slurp-sexp-moves-either-list-delimiter-across-a-sibling"
    (with-reduced-input-state (forward output)
        (reduce-once (input-state :buffer "(list alpha) beta" :cursor-pos 7)
                     :alt-ctrl-right)
      (is-input-state forward :buffer "(list alpha beta)" :cursor-pos 7)
      (expect :suggest-update :to-be output))
    (with-reduced-input-state (backward output)
        (reduce-once (input-state :buffer "alpha (list beta)" :cursor-pos 8)
                     :alt-ctrl-left)
      (is-input-state backward :buffer "(alpha list beta)" :cursor-pos 8)
      (expect :suggest-update :to-be output)))

  (it "barf-sexp-moves-either-list-delimiter-across-a-child"
    (with-reduced-input-state (forward output)
        (reduce-once (input-state :buffer "(list alpha beta)" :cursor-pos 7)
                     :shift-alt-ctrl-right)
      (is-input-state forward :buffer "(list alpha) beta" :cursor-pos 7)
      (expect :suggest-update :to-be output))
    (with-reduced-input-state (backward output)
        (reduce-once (input-state :buffer "(list alpha beta)" :cursor-pos 7)
                     :shift-alt-ctrl-left)
      (is-input-state backward :buffer "list (alpha beta)" :cursor-pos 7)
      (expect :suggest-update :to-be output)))

  (it "sexp-scanning-keeps-string-and-comment-delimiters-opaque"
    (let* ((buffer (concatenate 'string
                                "(list \"(fake)\" ; ) ignored"
                                (string #\Newline)
                                " tail)"))
           (literal-start (search "\"(fake)\"" buffer))
           (comment-start (search ";" buffer))
           (comment-paren (search ")" buffer :start2 comment-start))
           (tail-start (search "tail" buffer)))
      (with-reduced-input-state (after-string string-output)
          (reduce-once (input-state :buffer buffer
                                    :cursor-pos (1+ literal-start))
                       :alt-ctrl-f)
        (is-input-state after-string
                        :buffer buffer
                        :cursor-pos (+ literal-start (length "\"(fake)\"")))
        (expect :redraw :to-be string-output))
      (with-reduced-input-state (after-comment comment-output)
          (reduce-once (input-state :buffer buffer
                                    :cursor-pos comment-paren)
                       :alt-ctrl-f)
        (is-input-state after-comment
                        :buffer buffer
                        :cursor-pos (+ tail-start (length "tail")))
        (expect :redraw :to-be comment-output))))

  (it "sexp-scanning-keeps-parentheses-inside-escaped-symbols-opaque"
    (let* ((buffer "|symbol(paren)| tail")
           (cursor (search "(" buffer))
           (escaped-end (1+ (search "|" buffer :start2 1))))
      (with-reduced-input-state (moved output)
          (reduce-once (input-state :buffer buffer :cursor-pos cursor)
                       :alt-ctrl-f)
        (is-input-state moved :buffer buffer :cursor-pos escaped-end)
        (expect :redraw :to-be output))))

  (it "command-island-delimiters-do-not-produce-host-structure-actions"
    (let* ((buffer "(echo (inner))")
           (cursor (search "inner" buffer))
           (state (input-state :buffer buffer :cursor-pos cursor)))
      (with-reduced-input-state (unchanged output)
          (reduce-once state :alt-ctrl-f)
        (is-input-state unchanged :buffer buffer :cursor-pos cursor)
        (expect :none :to-be output)))
    (let ((buffer "(echo (inner))"))
      (with-reduced-input-state (outside output)
          (reduce-once (input-state :buffer buffer :cursor-pos 0) :alt-ctrl-f)
        (is-input-state outside :buffer buffer :cursor-pos (length buffer))
        (expect :redraw :to-be output))))

  (it "incomplete-and-invalid-inputs-do-not-change"
    (with-reduced-input-state (incomplete incomplete-output)
        (reduce-once (input-state :buffer "(list alpha" :cursor-pos 6)
                     :alt-ctrl-f)
      (is-input-state incomplete :buffer "(list alpha" :cursor-pos 6)
      (expect :none :to-be incomplete-output))
    (with-reduced-input-state (invalid invalid-output)
        (reduce-once (input-state :buffer ")" :cursor-pos 0)
                     :alt-ctrl-f)
      (is-input-state invalid :buffer ")" :cursor-pos 0)
      (expect :none :to-be invalid-output)))

  (it "structural-action-bindings-are-valid-and-match-terminal-keys"
    (let ((valid-keys (nshell.presentation::input-dispatch-valid-key-names))
          (valid-actions (nshell.presentation::input-dispatch-valid-action-names)))
      (expect :forward-sexp :to-be
              (nshell.presentation::input-dispatch-binding-action-name :alt-ctrl-f))
      (expect :backward-sexp :to-be
              (nshell.presentation::input-dispatch-binding-action-name :alt-ctrl-b))
      (expect :up-list :to-be
              (nshell.presentation::input-dispatch-binding-action-name :alt-ctrl-u))
      (expect :down-list :to-be
              (nshell.presentation::input-dispatch-binding-action-name :alt-ctrl-d))
      (expect :delete-forward-sexp :to-be
              (nshell.presentation::input-dispatch-binding-action-name :alt-ctrl-k))
      (expect :delete-backward-sexp :to-be
              (nshell.presentation::input-dispatch-binding-action-name :alt-ctrl-delete))
      (expect :slurp-forward :to-be
              (nshell.presentation::input-dispatch-binding-action-name :alt-ctrl-right))
      (expect :slurp-backward :to-be
              (nshell.presentation::input-dispatch-binding-action-name :alt-ctrl-left))
      (expect :barf-forward :to-be
              (nshell.presentation::input-dispatch-binding-action-name :shift-alt-ctrl-right))
      (expect :barf-backward :to-be
              (nshell.presentation::input-dispatch-binding-action-name :shift-alt-ctrl-left))
      (expect (member "alt-ctrl-delete" valid-keys :test #'string=) :to-be-truthy)
      (expect (member "shift-alt-ctrl-right" valid-keys :test #'string=) :to-be-truthy)
      (expect (member "forward-sexp" valid-actions :test #'string=) :to-be-truthy)
      (expect (member "delete-backward-sexp" valid-actions :test #'string=) :to-be-truthy)))

  (it "terminal-decoder-recognizes-meta-control-letter-and-delete-chords"
    (dolist (case '((2 :alt-ctrl-b)
                    (4 :alt-ctrl-d)
                    (6 :alt-ctrl-f)
                    (11 :alt-ctrl-k)
                    (21 :alt-ctrl-u)))
      (let ((event
              (single-key-event-from-string
               (esc-sequence (string (code-char (first case)))))))
        (expect (second case) :to-be
                (nshell.domain.input:key-event-type event))))
    (let ((event (single-key-event-from-string (esc-sequence "[3;7~"))))
      (expect :alt-ctrl-delete :to-be
              (nshell.domain.input:key-event-type event))))

  (it "terminal-decoder-preserves-modified-arrow-key-names"
    (dolist (case '(("[1;7C" :alt-ctrl-right)
                    ("[1;7D" :alt-ctrl-left)
                    ("[1;8C" :shift-alt-ctrl-right)
                    ("[1;8D" :shift-alt-ctrl-left)))
      (let ((event (single-key-event-from-string (esc-sequence (first case)))))
        (expect (second case) :to-be
                (nshell.domain.input:key-event-type event))))))
