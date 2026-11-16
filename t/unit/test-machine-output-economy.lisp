(in-package #:nshell/test)

;;; Output economy of ux/U6: cleaning terminal control out of captured output
;;; and cutting long output to its head and tail around a fixed marker.

(defun machine-economy-text (&rest parts)
  "Concatenate PARTS; a character code in PARTS stands for that character."
  (apply #'concatenate 'string
         (mapcar (lambda (part)
                   (if (integerp part) (string (code-char part)) part))
                 parts)))

(defun machine-economy-numbered-lines (count)
  (with-output-to-string (out)
    (loop for index from 1 to count
          do (format out "line ~D~%" index))))

(defun machine-economy-utf-8-length (text)
  (length (sb-ext:string-to-octets text :external-format :utf-8)))

(defun machine-economy-count-of (needle text)
  (loop for start = 0 then (+ found (length needle))
        for found = (search needle text :start2 start)
        while found
        count t))

(defun machine-economy-marker-line (text)
  (find-if (lambda (line) (search " omitted …" line))
           (uiop:split-string text :separator '(#\Newline))))

(describe "machine output cleaning"
  (it "strips CSI color and cursor sequences"
    (expect (nshell.feature.machine:clean-output-text
             (machine-economy-text 27 "[1;31mred" 27 "[0m " 27 "[2K" 27 "[10;5Hok" 27 "[?25l"))
            :to-equal "red ok"))

  (it "strips OSC sequences ended by BEL or ST and two-character escapes"
    (expect (nshell.feature.machine:clean-output-text
             (machine-economy-text 27 "]0;title" 7 "a" 27 "]8;;http://x" 27 "\\b"
                                   27 "7c" 27 "(Bd" 27 "="))
            :to-equal "abcd"))

  (it "strips C1 CSI sequences"
    (expect (nshell.feature.machine:clean-output-text
             (machine-economy-text #x9b "32mgreen" #x9b "0m"))
            :to-equal "green"))

  (it "removes C0 and C1 controls but keeps newline and tab"
    (expect (nshell.feature.machine:clean-output-text
             (machine-economy-text "a" 0 "b" 7 "c" 8 "d" #x7f "e" #x85 "f" 9 "g" 10))
            :to-equal (machine-economy-text "abcdef" 9 "g" 10)))

  (it "keeps only the last carriage-return segment of a progress line"
    (expect (nshell.feature.machine:clean-output-text
             (machine-economy-text "progress 10%" 13 "progress 55%" 13 "progress 100%" 10
                                   "done" 10))
            :to-equal (machine-economy-text "progress 100%" 10 "done" 10)))

  (it "ignores escape sequences when deciding whether a progress line was overwritten"
    (expect (nshell.feature.machine:clean-output-text
             (machine-economy-text "10%" 13 27 "[K" "100%"))
            :to-equal "100%"))

  (it "treats CR LF as a newline and keeps a segment followed only by CR"
    (expect (nshell.feature.machine:clean-output-text
             (machine-economy-text "one" 13 10 "two" 13 13 10 "three" 13))
            :to-equal (machine-economy-text "one" 10 "two" 10 "three"))))

(describe "machine output truncation"
  (it "returns text within the limit unchanged"
    (let ((text (machine-economy-numbered-lines 100)))
      (multiple-value-bind (shown truncated)
          (nshell.feature.machine:economize-output-text text)
        (expect shown :to-equal text)
        (expect truncated :to-be-null)))
    (multiple-value-bind (shown truncated)
        (nshell.feature.machine:economize-output-text "abcd" :max-bytes 4)
      (expect shown :to-equal "abcd")
      (expect truncated :to-be-null)))

  (it "keeps ten head and ten tail lines of a 9120-line output"
    (let* ((text (machine-economy-numbered-lines 9120))
           (shown (nshell.feature.machine:economize-output-text text))
           (lines (uiop:split-string (string-right-trim '(#\Newline) shown)
                                     :separator '(#\Newline))))
      (expect (machine-economy-count-of "… 9,100 lines omitted …" shown) :to-be 1)
      (expect (length lines) :to-be 21)
      (expect (subseq lines 0 10)
              :to-equal (loop for index from 1 to 10
                              collect (format nil "line ~D" index)))
      (expect (nth 10 lines) :to-equal "… 9,100 lines omitted …")
      (expect (subseq lines 11)
              :to-equal (loop for index from 9111 to 9120
                              collect (format nil "line ~D" index)))
      (expect (nth-value 1 (nshell.feature.machine:economize-output-text text))
              :to-be-truthy)))

  (it "writes the omitted-line count with comma thousands separators"
    (flet ((marker-for (omitted)
             (machine-economy-marker-line
              (nshell.feature.machine:economize-output-text
               (machine-economy-numbered-lines (+ omitted 2))
               :max-bytes 8 :head-lines 1 :tail-lines 1))))
      (expect (marker-for 999) :to-equal "… 999 lines omitted …")
      (expect (marker-for 1000) :to-equal "… 1,000 lines omitted …"))
    (let ((text (make-string 1234569 :initial-element #\Newline)))
      (expect (machine-economy-marker-line
               (nshell.feature.machine:economize-output-text
                text :max-bytes 8 :head-lines 1 :tail-lines 1))
              :to-equal "… 1,234,567 lines omitted …")))

  (it "cuts a single huge line to half the limit on each side with a bytes marker"
    (let* ((text (make-string 100000 :initial-element #\x))
           (shown (nshell.feature.machine:economize-output-text text :max-bytes 1000))
           (marker (machine-economy-marker-line shown)))
      (expect marker :to-equal "… 99,500 bytes omitted …")
      (expect (search "lines omitted" shown) :to-be-null)
      (expect (<= (machine-economy-utf-8-length shown)
                  (+ 1000 (machine-economy-utf-8-length marker) 2))
              :to-be-truthy)
      (expect (subseq shown 0 500) :to-equal (make-string 500 :initial-element #\x))
      (expect (char shown 500) :to-be #\Newline)))

  (it "bounds the shown text when the kept lines are long"
    (let* ((long-line (format nil "~A~%" (make-string 5000 :initial-element #\y)))
           (text (apply #'concatenate 'string
                        (loop repeat 40 collect long-line)))
           (shown (nshell.feature.machine:economize-output-text text))
           (marker (machine-economy-marker-line shown)))
      (expect marker :to-equal "… 20 lines omitted …")
      (expect (<= (machine-economy-utf-8-length shown)
                  (+ 32768 (machine-economy-utf-8-length marker) 2))
              :to-be-truthy)))

  (it "never splits a multibyte character"
    (let* ((half (make-string 500 :initial-element (code-char #x3042)))
           (text (format nil "~A~%~A" half half))
           (shown (nshell.feature.machine:economize-output-text text :max-bytes 101))
           (kept (make-string 16 :initial-element (code-char #x3042))))
      ;; 50 bytes per side hold 16 three-byte characters.
      (expect (uiop:split-string shown :separator '(#\Newline))
              :to-equal (list kept "… 2,905 bytes omitted …" kept)))))

(describe "machine envelope output for text"
  (it "counts bytes and lines of the whole cleaned text"
    (let* ((raw (with-output-to-string (out)
                  (loop for index from 1 to 9120
                        do (format out "~C[32mline ~D~C[0m~%" (code-char 27) index
                                   (code-char 27)))))
           (cleaned (machine-economy-numbered-lines 9120))
           (output (nshell.feature.machine:envelope-output-for-text
                    raw :path "/cache/nshell/out/s_abcdef/1.txt")))
      (expect (nshell.feature.machine:envelope-output-bytes output)
              :to-be (machine-economy-utf-8-length cleaned))
      (expect (nshell.feature.machine:envelope-output-lines output) :to-be 9120)
      (expect (nshell.feature.machine:envelope-output-truncated output) :to-be-truthy)
      (expect (nshell.feature.machine:envelope-output-path output)
              :to-equal "/cache/nshell/out/s_abcdef/1.txt")
      (expect (search "… 9,100 lines omitted …"
                      (nshell.feature.machine:envelope-output-text output))
              :to-be-truthy)
      (let ((envelope (apply #'nshell.feature.machine:result-envelope
                             :stdout output
                             (let ((parts (machine-envelope-parts)))
                               (remf parts :stdout)
                               parts))))
        (expect (machine-envelope-failures (machine-envelope-parse envelope))
                :to-be-null))))

  (it "matches output-from-text for short output and drops an unused path"
    (dolist (raw '("" "3
" "a
b"))
      (let ((output (nshell.feature.machine:envelope-output-for-text
                     raw :path "/unused"))
            (expected (nshell.feature.machine:output-from-text raw)))
        (expect (nshell.feature.machine:envelope-output-text output)
                :to-equal (nshell.feature.machine:envelope-output-text expected))
        (expect (nshell.feature.machine:envelope-output-bytes output)
                :to-be (nshell.feature.machine:envelope-output-bytes expected))
        (expect (nshell.feature.machine:envelope-output-lines output)
                :to-be (nshell.feature.machine:envelope-output-lines expected))
        (expect (nshell.feature.machine:envelope-output-truncated output) :to-be-null)
        (expect (nshell.feature.machine:envelope-output-path output) :to-be-null)))))
