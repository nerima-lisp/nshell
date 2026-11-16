(in-package #:nshell.domain.expansion)

(defun %find-matching-brace (string start)
  "Return the index of the #\} matching the #\{ at START, or NIL if unbalanced."
  (loop with depth = 0
        for i from start below (length string)
        for ch = (char string i)
        do (cond ((char= ch #\{) (incf depth))
                 ((char= ch #\}) (decf depth) (when (zerop depth) (return i))))))

(defun %split-top-level-commas (string)
  "Split STRING on commas that are not nested inside braces."
  (let ((parts '()) (depth 0) (start 0))
    (loop for i from 0 below (length string)
          for ch = (char string i)
          do (cond ((char= ch #\{) (incf depth))
                   ((char= ch #\}) (decf depth))
                   ((and (char= ch #\,) (zerop depth))
                    (push (subseq string start i) parts)
                    (setf start (1+ i)))))
    (push (subseq string start) parts)
    (nreverse parts)))

(defun %brace-range-bounds (content)
  "Return endpoints and :INTEGER or :CHARACTER for a supported brace range."
  (let ((dots (search ".." content)))
    (when dots
      (let ((lo (subseq content 0 dots))
            (hi (subseq content (+ dots 2))))
        (cond
          ((and (plusp (length lo)) (every #'digit-char-p lo)
                (plusp (length hi)) (every #'digit-char-p hi))
           (values (parse-integer lo) (parse-integer hi) :integer))
          ((and (= 1 (length lo)) (alpha-char-p (char lo 0))
                (= 1 (length hi)) (alpha-char-p (char hi 0)))
           (values (char-code (char lo 0)) (char-code (char hi 0)) :character)))))))

(defun %brace-range-expansion (content)
  "Return expansions for a supported numeric or character range, or NIL."
  (multiple-value-bind (lo hi kind) (%brace-range-bounds content)
    (case kind
      (:integer
       (if (<= lo hi)
           (loop for n from lo to hi collect (princ-to-string n))
           (loop for n from lo downto hi collect (princ-to-string n))))
      (:character
       (if (<= lo hi)
           (loop for c from lo to hi collect (string (code-char c)))
           (loop for c from lo downto hi collect (string (code-char c))))))))

(defun %brace-expansion-options (content)
  "Return expansion options for one brace group CONTENT, or NIL when literal."
  (or (%brace-range-expansion content)
      (let ((parts (%split-top-level-commas content)))
        (when (> (length parts) 1) parts))))

(define-value-struct brace-expansion-frame
    ((input "" :type string)
     (open 0 :type fixnum)
     (close 0 :type fixnum)
     (prefix "" :type string)
     (content "" :type string)
     (suffix "" :type string)
     (options nil)))

(defun %brace-expansion-literal-results (frame suffix-expansions)
  (let ((literal (%brace-expansion-frame-literal frame)))
    (mapcar (lambda (suffix)
              (concatenate 'string literal suffix))
            suffix-expansions)))

(defun %brace-expansion-cartesian-product (frame suffix-expansions)
  (loop for option in (brace-expansion-frame-options frame)
        append (loop for option-expansion in (expand-braces option)
                     append (loop for suffix in suffix-expansions
                                  collect (concatenate 'string
                                                       (brace-expansion-frame-prefix frame)
                                                       option-expansion
                                                       suffix)))))

(defun %brace-expansion-frame (input open close)
  "Create the domain frame for the first matched brace group in INPUT."
  (let ((content (subseq input (1+ open) close)))
    (%make-brace-expansion-frame
     input
     open
     close
     (subseq input 0 open)
     content
     (subseq input (1+ close))
     (%brace-expansion-options content))))

(defun %brace-expansion-frame-literal (frame)
  "Return FRAME's literal brace text including the preserved prefix."
  (concatenate 'string
               (brace-expansion-frame-prefix frame)
               "{"
               (brace-expansion-frame-content frame)
               "}"))

(defun expand-braces (input)
  "Expand brace patterns {a,b,c} and ranges {1..5}/{a..e} in INPUT, returning a
list of strings (always at least one). A brace group with no top-level comma and
no valid range is left literal, matching shell behavior."
  (let ((open (position #\{ input)))
    (cond
      ((null open)
       (list input))
      (t
       (let ((close (%find-matching-brace input open)))
         (if (null close)
             (list input)
             (let* ((frame (%brace-expansion-frame input open close))
                    (suffix-expansions
                      (expand-braces (brace-expansion-frame-suffix frame))))
               (if (null (brace-expansion-frame-options frame))
                   (%brace-expansion-literal-results frame suffix-expansions)
                   (%brace-expansion-cartesian-product frame suffix-expansions)))))))))

(defun brace-expansion-p (input)
  "Return whether EXPAND-BRACES changes INPUT without enumerating its results.
INPUT carries the same quote and escape protection as for EXPAND-BRACES."
  (loop with start = 0
        for open = (position #\{ input :start start)
        while open
        for close = (%find-matching-brace input open)
        while close
        for content = (subseq input (1+ open) close)
        when (or (nth-value 2 (%brace-range-bounds content))
                 (rest (%split-top-level-commas content)))
          return t
        do (setf start (1+ close))
        finally (return nil)))
