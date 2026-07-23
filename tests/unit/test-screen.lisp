(in-package #:nshell/test)

(defun %esc (text)
  (concatenate 'string (string #\Esc) text))

(describe "screen-tests"
  (it "cell-raw-constructor-is-internal-boundary"
    (let ((cell (nshell.infrastructure.terminal::make-cell :character #\X :foreground "FF0000")))
      (expect (nshell.infrastructure.terminal::cell-p cell) :to-be-truthy)
      (expect #\X :to-equal (nshell.infrastructure.terminal:cell-character cell))
      (expect "FF0000" :to-equal (nshell.infrastructure.terminal:cell-foreground cell))
      (expect (nshell.infrastructure.terminal:cell-background cell) :to-be-null)
      (expect (fboundp 'nshell.infrastructure.terminal::%make-cell) :to-be-truthy)))

  (it "screen-cell-write-and-retrieval"
    (let ((screen (nshell.infrastructure.terminal:make-screen :width 4 :height 2)))
      (nshell.infrastructure.terminal:screen-put-cell
       screen 1 2 #\X :foreground "FF0000" :bold-p t)
      (let ((cell (nshell.infrastructure.terminal:screen-cell screen 1 2)))
        (expect #\X :to-equal (nshell.infrastructure.terminal:cell-character cell))
        (expect "FF0000" :to-equal (nshell.infrastructure.terminal:cell-foreground cell))
        (expect (nshell.infrastructure.terminal:cell-bold-p cell) :to-be-truthy))))

  (it "screen-string-and-line-rendering-with-attributes"
    (let ((screen (nshell.infrastructure.terminal:make-screen :width 10 :height 2)))
      (nshell.infrastructure.terminal:screen-put-string screen 0 1 "abc" :foreground "00FF00" :underline-p t)
      (expect #\a :to-equal (nshell.infrastructure.terminal:cell-character
                      (nshell.infrastructure.terminal:screen-cell screen 0 1)))
      (expect (nshell.infrastructure.terminal:cell-underline-p
           (nshell.infrastructure.terminal:screen-cell screen 0 2)) :to-be-truthy)
      (nshell.infrastructure.terminal:screen-put-line
       screen 1 "hello" :spans (list (list :start 1 :end 4 :role "FF0000")))
      (expect "FF0000" :to-equal (nshell.infrastructure.terminal:cell-foreground
                    (nshell.infrastructure.terminal:screen-cell screen 1 2)))))

  (it "screen-string-uses-terminal-cell-widths"
    (let ((screen (nshell.infrastructure.terminal:make-screen :width 6 :height 1)))
      (nshell.infrastructure.terminal:screen-put-string screen 0 0 "aあb")
      (expect #\a :to-equal (nshell.infrastructure.terminal:cell-character
                      (nshell.infrastructure.terminal:screen-cell screen 0 0)))
      (expect #\あ :to-equal (nshell.infrastructure.terminal:cell-character
                         (nshell.infrastructure.terminal:screen-cell screen 0 1)))
      (expect (nshell.infrastructure.terminal:cell-character
                 (nshell.infrastructure.terminal:screen-cell screen 0 2)) :to-be-null)
      (expect #\b :to-equal (nshell.infrastructure.terminal:cell-character
                      (nshell.infrastructure.terminal:screen-cell screen 0 3)))))

  (it "screen-string-does-not-render-partial-wide-character"
    (let ((screen (nshell.infrastructure.terminal:make-screen :width 3 :height 1)))
      (nshell.infrastructure.terminal:screen-put-string screen 0 2 "あ")
      (expect (nshell.infrastructure.terminal:cell-character
                 (nshell.infrastructure.terminal:screen-cell screen 0 2)) :to-be-null)))

  (it "screen-line-spans-follow-character-index-with-wide-characters"
    (let ((screen (nshell.infrastructure.terminal:make-screen :width 6 :height 1)))
      (nshell.infrastructure.terminal:screen-put-line
       screen 0 "aあb" :spans (list (list :start 1 :end 2 :role "00AAFF")))
      (expect "00AAFF" :to-equal (nshell.infrastructure.terminal:cell-foreground
                    (nshell.infrastructure.terminal:screen-cell screen 0 1)))
      (expect (nshell.infrastructure.terminal:cell-foreground
                 (nshell.infrastructure.terminal:screen-cell screen 0 3)) :to-be-null)))

  (it "screen-diff-unchanged-cells-produce-no-output"
    (let ((old (nshell.infrastructure.terminal:make-screen :width 5 :height 1))
          (new (nshell.infrastructure.terminal:make-screen :width 5 :height 1)))
      (nshell.infrastructure.terminal:screen-put-string old 0 0 "abc")
      (nshell.infrastructure.terminal:screen-put-string new 0 0 "abc")
      (let ((output (with-output-to-string (s)
                      (nshell.infrastructure.terminal:screen-render old new :stream s))))
        (expect "" :to-equal output))))

  (it "screen-diff-changed-cells-emit-ansi"
    (let ((old (nshell.infrastructure.terminal:make-screen :width 5 :height 1))
          (new (nshell.infrastructure.terminal:make-screen :width 5 :height 1)))
      (nshell.infrastructure.terminal:screen-put-string old 0 0 "abc")
      (nshell.infrastructure.terminal:screen-put-string new 0 0 "abc")
      (nshell.infrastructure.terminal:screen-put-cell new 0 1 #\x :foreground "00FF00")
      (let ((output (with-output-to-string (s)
                      (nshell.infrastructure.terminal:screen-render old new :stream s))))
        (expect (search (%esc "[1;2H") output) :to-be-truthy)
        (expect (search (%esc "[38;2;0;255;0m") output) :to-be-truthy)
        (expect (search "x" output) :to-be-truthy))))

  (it "screen-diff-cleared-cells-emit-space"
    (let ((old (nshell.infrastructure.terminal:make-screen :width 5 :height 1))
          (new (nshell.infrastructure.terminal:make-screen :width 5 :height 1)))
      (nshell.infrastructure.terminal:screen-put-string old 0 0 "abc")
      (nshell.infrastructure.terminal:screen-put-string new 0 0 "a")
      (let ((output (with-output-to-string (s)
                      (nshell.infrastructure.terminal:screen-render old new :stream s))))
        (expect (search (%esc "[1;2H") output) :to-be-truthy)
        (expect (search " " output) :to-be-truthy))))

  (it "screen-resize-preserves-existing-content"
    (let ((screen (nshell.infrastructure.terminal:make-screen :width 3 :height 2)))
      (nshell.infrastructure.terminal:screen-put-string screen 0 0 "ab")
      (nshell.infrastructure.terminal:screen-put-cell screen 1 2 #\Z)
      (nshell.infrastructure.terminal:screen-resize screen 5 3)
      (expect 5 :to-equal (nshell.infrastructure.terminal:screen-width screen))
      (expect 3 :to-equal (nshell.infrastructure.terminal:screen-height screen))
      (expect #\a :to-equal (nshell.infrastructure.terminal:cell-character
                      (nshell.infrastructure.terminal:screen-cell screen 0 0)))
      (expect #\Z :to-equal (nshell.infrastructure.terminal:cell-character
                      (nshell.infrastructure.terminal:screen-cell screen 1 2)))))

  (it "screen-clear-marks-all-cells-empty"
    (let ((screen (nshell.infrastructure.terminal:make-screen :width 3 :height 2)))
      (nshell.infrastructure.terminal:screen-put-string screen 0 0 "abc")
      (nshell.infrastructure.terminal:screen-clear screen)
      (loop for row below (nshell.infrastructure.terminal:screen-height screen)
            do (loop for col below (nshell.infrastructure.terminal:screen-width screen)
                     do (expect (nshell.infrastructure.terminal:cell-character
                                   (nshell.infrastructure.terminal:screen-cell screen row col)) :to-be-null))))))
