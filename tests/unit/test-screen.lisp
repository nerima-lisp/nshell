(in-package #:nshell/test)

(def-suite screen-tests
  :description "Terminal screen diff rendering tests"
  :in nshell-tests)

(in-suite screen-tests)

(defun %esc (text)
  (concatenate 'string (string #\Esc) text))

(test cell-raw-constructor-is-internal-boundary
  (let ((cell (nshell.infrastructure.terminal::make-cell :character #\X :foreground "FF0000")))
    (is (nshell.infrastructure.terminal::cell-p cell))
    (is (char= #\X (nshell.infrastructure.terminal:cell-character cell)))
    (is (string= "FF0000" (nshell.infrastructure.terminal:cell-foreground cell)))
    (is (null (nshell.infrastructure.terminal:cell-background cell)))
    (is (fboundp 'nshell.infrastructure.terminal::%make-cell))))

(test screen-cell-write-and-retrieval
  (let ((screen (nshell.infrastructure.terminal:make-screen :width 4 :height 2)))
    (nshell.infrastructure.terminal:screen-put-cell
     screen 1 2 #\X :foreground "FF0000" :bold-p t)
    (let ((cell (nshell.infrastructure.terminal:screen-cell screen 1 2)))
      (is (char= #\X (nshell.infrastructure.terminal:cell-character cell)))
      (is (string= "FF0000" (nshell.infrastructure.terminal:cell-foreground cell)))
      (is (nshell.infrastructure.terminal:cell-bold-p cell)))))

(test screen-string-and-line-rendering-with-attributes
  (let ((screen (nshell.infrastructure.terminal:make-screen :width 10 :height 2)))
    (nshell.infrastructure.terminal:screen-put-string screen 0 1 "abc" :foreground "00FF00" :underline-p t)
    (is (char= #\a (nshell.infrastructure.terminal:cell-character
                    (nshell.infrastructure.terminal:screen-cell screen 0 1))))
    (is (nshell.infrastructure.terminal:cell-underline-p
         (nshell.infrastructure.terminal:screen-cell screen 0 2)))
    (nshell.infrastructure.terminal:screen-put-line
     screen 1 "hello" :spans (list (list :start 1 :end 4 :role "FF0000")))
    (is (string= "FF0000"
                 (nshell.infrastructure.terminal:cell-foreground
                  (nshell.infrastructure.terminal:screen-cell screen 1 2))))))

(test screen-string-uses-terminal-cell-widths
  (let ((screen (nshell.infrastructure.terminal:make-screen :width 6 :height 1)))
    (nshell.infrastructure.terminal:screen-put-string screen 0 0 "aあb")
    (is (char= #\a (nshell.infrastructure.terminal:cell-character
                    (nshell.infrastructure.terminal:screen-cell screen 0 0))))
    (is (char= #\あ (nshell.infrastructure.terminal:cell-character
                       (nshell.infrastructure.terminal:screen-cell screen 0 1))))
    (is (null (nshell.infrastructure.terminal:cell-character
               (nshell.infrastructure.terminal:screen-cell screen 0 2))))
    (is (char= #\b (nshell.infrastructure.terminal:cell-character
                    (nshell.infrastructure.terminal:screen-cell screen 0 3))))))

(test screen-string-does-not-render-partial-wide-character
  (let ((screen (nshell.infrastructure.terminal:make-screen :width 3 :height 1)))
    (nshell.infrastructure.terminal:screen-put-string screen 0 2 "あ")
    (is (null (nshell.infrastructure.terminal:cell-character
               (nshell.infrastructure.terminal:screen-cell screen 0 2))))))

(test screen-line-spans-follow-character-index-with-wide-characters
  (let ((screen (nshell.infrastructure.terminal:make-screen :width 6 :height 1)))
    (nshell.infrastructure.terminal:screen-put-line
     screen 0 "aあb" :spans (list (list :start 1 :end 2 :role "00AAFF")))
    (is (string= "00AAFF"
                 (nshell.infrastructure.terminal:cell-foreground
                  (nshell.infrastructure.terminal:screen-cell screen 0 1))))
    (is (null (nshell.infrastructure.terminal:cell-foreground
               (nshell.infrastructure.terminal:screen-cell screen 0 3))))))

(test screen-diff-unchanged-cells-produce-no-output
  (let ((old (nshell.infrastructure.terminal:make-screen :width 5 :height 1))
        (new (nshell.infrastructure.terminal:make-screen :width 5 :height 1)))
    (nshell.infrastructure.terminal:screen-put-string old 0 0 "abc")
    (nshell.infrastructure.terminal:screen-put-string new 0 0 "abc")
    (let ((output (with-output-to-string (s)
                    (nshell.infrastructure.terminal:screen-render old new :stream s))))
      (is (string= "" output)))))

(test screen-diff-changed-cells-emit-ansi
  (let ((old (nshell.infrastructure.terminal:make-screen :width 5 :height 1))
        (new (nshell.infrastructure.terminal:make-screen :width 5 :height 1)))
    (nshell.infrastructure.terminal:screen-put-string old 0 0 "abc")
    (nshell.infrastructure.terminal:screen-put-string new 0 0 "abc")
    (nshell.infrastructure.terminal:screen-put-cell new 0 1 #\x :foreground "00FF00")
    (let ((output (with-output-to-string (s)
                    (nshell.infrastructure.terminal:screen-render old new :stream s))))
      (is (search (%esc "[1;2H") output))
      (is (search (%esc "[38;2;0;255;0m") output))
      (is (search "x" output)))))

(test screen-diff-cleared-cells-emit-space
  (let ((old (nshell.infrastructure.terminal:make-screen :width 5 :height 1))
        (new (nshell.infrastructure.terminal:make-screen :width 5 :height 1)))
    (nshell.infrastructure.terminal:screen-put-string old 0 0 "abc")
    (nshell.infrastructure.terminal:screen-put-string new 0 0 "a")
    (let ((output (with-output-to-string (s)
                    (nshell.infrastructure.terminal:screen-render old new :stream s))))
      (is (search (%esc "[1;2H") output))
      (is (search " " output)))))

(test screen-resize-preserves-existing-content
  (let ((screen (nshell.infrastructure.terminal:make-screen :width 3 :height 2)))
    (nshell.infrastructure.terminal:screen-put-string screen 0 0 "ab")
    (nshell.infrastructure.terminal:screen-put-cell screen 1 2 #\Z)
    (nshell.infrastructure.terminal:screen-resize screen 5 3)
    (is (= 5 (nshell.infrastructure.terminal:screen-width screen)))
    (is (= 3 (nshell.infrastructure.terminal:screen-height screen)))
    (is (char= #\a (nshell.infrastructure.terminal:cell-character
                    (nshell.infrastructure.terminal:screen-cell screen 0 0))))
    (is (char= #\Z (nshell.infrastructure.terminal:cell-character
                    (nshell.infrastructure.terminal:screen-cell screen 1 2))))))

(test screen-clear-marks-all-cells-empty
  (let ((screen (nshell.infrastructure.terminal:make-screen :width 3 :height 2)))
    (nshell.infrastructure.terminal:screen-put-string screen 0 0 "abc")
    (nshell.infrastructure.terminal:screen-clear screen)
    (loop for row below (nshell.infrastructure.terminal:screen-height screen)
          do (loop for col below (nshell.infrastructure.terminal:screen-width screen)
                   do (is (null (nshell.infrastructure.terminal:cell-character
                                 (nshell.infrastructure.terminal:screen-cell screen row col))))))))
