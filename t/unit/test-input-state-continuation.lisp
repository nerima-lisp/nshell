(in-package #:nshell/test)

(describe "e03-input-continuation"
  (it "e03-enter-inserts-scanner-indentation-at-the-current-cursor"
      (let* ((source "echo $(echo tail")
             (cursor 12)
             (scan-result
              (nshell.domain.parsing:scan-input
               source
               :cursor cursor
               :reader-context :bare-line
               :indent-width nshell.presentation::+editor-indent-width+))
             (indent
              (nshell.domain.parsing:scan-result-next-indent scan-result))
             (expected-buffer
              (concatenate 'string
                           (subseq source 0 cursor)
                           (string #\Newline)
                           (make-string indent :initial-element #\Space)
                           (subseq source cursor))))
        (expect 8 :to-equal indent)
        (expect :incomplete :to-be
                (nshell.domain.parsing:scan-result-status scan-result))
        (multiple-value-bind (continued-state output)
            (reduce-once (input-state :buffer source :cursor-pos cursor) :enter)
          (expect :suggest-update :to-be output)
          (expect expected-buffer :to-equal
                  (nshell.presentation:input-state-buffer continued-state))
          (expect (+ cursor 1 indent) :to-equal
                  (nshell.presentation:input-state-cursor-pos continued-state)))))
  (it "K04-incomplete-parenthesis-enters-continuation-before-cancel"
    (cl-weave:expect-assertions 7)
    (let* ((source "(touch K04_SHOULD_NOT_EXIST")
             (cursor (length source))
             (scan-result
               (nshell.presentation::%repl-input-scan-result
                source cursor :sexp))
             (indent
               (nshell.domain.parsing:scan-result-next-indent scan-result))
             (expected-buffer
               (concatenate 'string
                            source
                            (string #\Newline)
                            (make-string indent :initial-element #\Space))))
        (expect :incomplete :to-be
                (nshell.domain.parsing:scan-result-status scan-result))
        (multiple-value-bind (continued-state enter-output)
            (reduce-once (input-state :buffer source :cursor-pos cursor) :enter)
          (expect :suggest-update :to-be enter-output)
          (expect expected-buffer :to-equal
                  (nshell.presentation:input-state-buffer continued-state))
          (expect (+ cursor 1 indent) :to-equal
                  (nshell.presentation:input-state-cursor-pos continued-state))
          (multiple-value-bind (cancelled-state cancel-output)
              (reduce-once continued-state :ctrl-c)
            (expect :redraw :to-be cancel-output)
            (expect "" :to-equal
                    (nshell.presentation:input-state-buffer cancelled-state))
            (expect 0 :to-equal
                    (nshell.presentation:input-state-cursor-pos cancelled-state))))))

  (it "e03-complete-and-invalid-enter-leave-buffer-for-execute-handler"
    (dolist (case '(("echo > out" :complete)
                    ("echo >" :invalid)))
      (destructuring-bind (source expected-status) case
        (let* ((cursor (length source))
               (scan-result
                 (nshell.domain.parsing:scan-input
                  source
                  :cursor cursor
                  :reader-context :bare-line
                  :indent-width nshell.presentation::+editor-indent-width+))
               (state (input-state :buffer source :cursor-pos cursor)))
          (expect expected-status :to-be
                  (nshell.domain.parsing:scan-result-status scan-result))
          (multiple-value-bind (next-state output)
              (reduce-once state :enter)
            (expect :execute :to-be output)
            (expect source :to-equal
                    (nshell.presentation:input-state-buffer next-state))
            (expect cursor :to-equal
                    (nshell.presentation:input-state-cursor-pos next-state)))))))

  (it "e03-vertical-motion-keeps-a-preferred-visual-column-across-short-lines"
    (let ((state (input-state :buffer (format nil "abcdef~%xy~%abcdef") :cursor-pos 14)))
      (multiple-value-bind (short-line up-output)
          (reduce-once state :up)
        (expect :redraw :to-be up-output)
        (expect 9 :to-equal
                (nshell.presentation:input-state-cursor-pos short-line))
        (expect 4 :to-equal
                (nshell.presentation::input-state-preferred-visual-column short-line))
        (multiple-value-bind (first-line first-up-output)
            (reduce-once short-line :up)
          (expect :redraw :to-be first-up-output)
          (expect 4 :to-equal
                  (nshell.presentation:input-state-cursor-pos first-line))
          (expect 4 :to-equal
                  (nshell.presentation::input-state-preferred-visual-column first-line))
          (multiple-value-bind (short-line-again down-output)
              (reduce-once first-line :down)
            (expect :redraw :to-be down-output)
            (expect 9 :to-equal
                    (nshell.presentation:input-state-cursor-pos short-line-again))
            (multiple-value-bind (last-line last-down-output)
                (reduce-once short-line-again :down)
              (expect :redraw :to-be last-down-output)
              (expect 14 :to-equal
                      (nshell.presentation:input-state-cursor-pos last-line))))))))

  (it "e03-vertical-motion-uses-terminal-cells-for-wide-graphemes-and-tabs"
    (multiple-value-bind (wide-target wide-output)
        (reduce-once (input-state :buffer (format nil "あx~%1") :cursor-pos 4) :up)
      (expect :redraw :to-be wide-output)
      (expect 0 :to-equal
              (nshell.presentation:input-state-cursor-pos wide-target)))
    (multiple-value-bind (tab-target tab-output)
        (reduce-once (input-state :buffer (format nil "abc~Az~%1234" (string #\Tab)) :cursor-pos 10) :up)
      (expect :redraw :to-be tab-output)
      (expect 3 :to-equal
              (nshell.presentation:input-state-cursor-pos tab-target))))

  (it "e03-vertical-motion-passes-history-at-multiline-endpoints"
    (let ((first-line (input-state :buffer (format nil "one~%two")
                                   :cursor-pos 1
                                   :preferred-visual-column 3))
          (last-line (input-state :buffer (format nil "one~%two")
                                  :cursor-pos 7
                                  :preferred-visual-column 4))
          (single-line (input-state :buffer "echo" :cursor-pos 2)))
      (multiple-value-bind (same-state output)
          (reduce-once first-line :up)
        (expect :history-prev :to-be output)
        (expect 1 :to-equal
                (nshell.presentation:input-state-cursor-pos same-state))
        (expect nil :to-equal
                (nshell.presentation::input-state-preferred-visual-column same-state)))
      (multiple-value-bind (same-state output)
          (reduce-once last-line :down)
        (expect :history-next :to-be output)
        (expect 7 :to-equal
                (nshell.presentation:input-state-cursor-pos same-state))
        (expect nil :to-equal
                (nshell.presentation::input-state-preferred-visual-column same-state)))
      (multiple-value-bind (same-state output)
          (reduce-once single-line :up)
        (expect :history-prev :to-be output)
        (expect 2 :to-equal
                (nshell.presentation:input-state-cursor-pos same-state)))))

  (it "e03-editing-resets-the-preferred-visual-column"
    (let ((state (input-state :buffer (format nil "one~%two") :cursor-pos 2 :preferred-visual-column 5)))
      (multiple-value-bind (edited-state output)
          (reduce-once state :char #\!)
        (expect :suggest-update :to-be output)
        (expect nil :to-equal
                (nshell.presentation::input-state-preferred-visual-column edited-state)))
      (multiple-value-bind (moved-state output)
          (reduce-once state :left)
        (expect :redraw :to-be output)
        (expect nil :to-equal
                (nshell.presentation::input-state-preferred-visual-column moved-state)))))

  (it "e03-ctrl-e-moves-to-the-physical-line-end-and-keeps-single-line-behavior"
    (multiple-value-bind (multiline-state multiline-output)
        (reduce-once (input-state :buffer (format nil "one~%two tail") :cursor-pos 5) :ctrl-e)
      (expect :redraw :to-be multiline-output)
      (expect (length (format nil "one~%two tail")) :to-equal
              (nshell.presentation:input-state-cursor-pos multiline-state)))
    (multiple-value-bind (single-line-state single-line-output)
        (reduce-once (input-state :buffer "abc" :cursor-pos 0) :ctrl-e)
      (expect :redraw :to-be single-line-output)
      (expect 3 :to-equal
              (nshell.presentation:input-state-cursor-pos single-line-state))))

  (it "e03-matching-delimiter-spans-follow-the-nested-shell-group-at-point"
    (let ((source "echo $( (echo X) )"))
      (let ((nshell.presentation::*input-state*
              (input-state :buffer source :cursor-pos 8)))
        (expect (list (list 8 9) (list 15 16))
                :to-equal
                (nshell.presentation::%active-matching-delimiter-spans)))
      (let ((nshell.presentation::*input-state*
              (input-state :buffer source :cursor-pos 17)))
        (expect (list (list 6 7) (list 17 18))
                :to-equal
                (nshell.presentation::%active-matching-delimiter-spans)))))
  (it "e03-matching-delimiters-use-the-stable-reverse-video-marker"
    (with-repl-test-state
      (let* ((source "echo $( (echo X) )")
             (nshell.presentation::*input-state*
               (input-state :buffer source :cursor-pos 8))
             (spans (nshell.presentation::%active-matching-delimiter-spans))
             (output
               (capture-standard-output
                 (nshell.presentation::render-edit-buffer
                  source
                  (nshell.domain.configuration:config-theme
                   nshell.presentation::*config*)
                  :matching-spans spans)))
             (open-marker (format nil "~c[7m(~c[0m" #\Esc #\Esc))
             (close-marker (format nil "~c[7m)~c[0m" #\Esc #\Esc)))
        (expect output :to-contain open-marker)
        (expect output :to-contain close-marker))))
)