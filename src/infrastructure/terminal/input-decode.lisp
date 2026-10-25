(in-package #:nshell.infrastructure.terminal)

(defun mouse-modifiers (button-code)
  (loop for (mask modifier) in '((4 :shift) (8 :alt) (16 :ctrl))
        when (not (zerop (logand button-code mask)))
          collect modifier))

(defun mouse-event-kind (button-code final)
  (cond
    ((char= final #\m) :release)
    ((not (zerop (logand button-code 64)))
     (case (logand button-code 3)
       (0 :wheel-up)
       (1 :wheel-down)
       (otherwise :wheel)))
    ((not (zerop (logand button-code 32))) :drag)
    (t :press)))

(defun decode-sgr-mouse-event (body final)
  "Decode an SGR mouse report body such as \"<0;10;5\".

Returns NIL when BODY/FINAL is not an SGR mouse report."
  (when (and (> (length body) 0)
             (char= (char body 0) #\<)
             (or (char= final #\M) (char= final #\m)))
    (let* ((parts (split-string-on-char (subseq body 1) #\;))
           (button-code (parse-integer-or-nil (or (first parts) "")))
           (column (parse-integer-or-nil (or (second parts) "")))
           (row (parse-integer-or-nil (or (third parts) ""))))
      (if (and button-code column row)
          (make-key-event :mouse nil button-code
                          (list :protocol :sgr
                                :button (logand button-code 3)
                                :button-code button-code
                                :column column
                                :row row
                                :event (mouse-event-kind button-code final)
                                :modifiers (mouse-modifiers button-code)))
          (make-key-event :unknown)))))

(defun csi-modifier (body)
  (let* ((parts (split-string-on-char body #\;))
         (modifier-text (second parts)))
    (parse-integer-or-nil (or modifier-text ""))))

(defun modifier-prefixes (modifier)
  (lookup-key-event-type modifier +modifier-prefix-specs+))

(defun modified-arrow-type (base modifier)
  (let ((prefixes (modifier-prefixes modifier)))
    (if prefixes
        (intern (format nil "~{~a-~}~a" prefixes (symbol-name base)) "KEYWORD")
        base)))

(defun decode-csi-tilde (body)
  (let* ((parts (split-string-on-char body #\;))
         (code (parse-integer-or-nil (first parts)))
         (modifier (csi-modifier body))
         (event (key-event-from-spec code +csi-tilde-specs+)))
    (or (and (eql code 3)
             (eql modifier 7)
             (make-key-event (modified-arrow-type :delete modifier)))
        event
        (make-key-event :unknown nil code))))

(defun decode-csi-final (body final)
  (or (when (and (char= final #\R)
                 (let ((parts (split-string-on-char body #\;)))
                   (and (= (length parts) 2)
                        (every (lambda (part)
                                 (and (plusp (length part))
                                      (every #'digit-char-p part)))
                               parts))))
        (make-key-event :ignore))
      (decode-sgr-mouse-event body final)
      (let ((arrow-type (lookup-key-event-type final +csi-arrow-specs+)))
        (when arrow-type
          (make-key-event (modified-arrow-type arrow-type (csi-modifier body)))))
      (key-event-from-spec final +csi-final-specs+)
      (when (char= final #\~)
        (decode-csi-tilde body))
      (make-key-event :unknown)))

(defun decode-csi-sequence (sequence)
  (if (zerop (length sequence))
      (make-key-event :escape)
      (let* ((final (char sequence (1- (length sequence))))
             (body (subseq sequence 0 (1- (length sequence)))))
        (decode-csi-final body final))))

(defun decode-ss3-sequence (sequence)
  (if (zerop (length sequence))
      (make-key-event :escape)
      (or (key-event-from-spec (char sequence 0) +ss3-specs+)
          (make-key-event :unknown))))

(defun decode-meta-key (ch)
  "Decode an ESC-prefixed Meta key chord, returning NIL for unknown prefixes."
  (or (case (char-code ch)
        (2 (make-key-event :alt-ctrl-b))
        (4 (make-key-event :alt-ctrl-d))
        (6 (make-key-event :alt-ctrl-f))
        (11 (make-key-event :alt-ctrl-k))
        (21 (make-key-event :alt-ctrl-u)))
      (key-event-from-spec (char-code ch) +meta-code-specs+)
      (key-event-from-spec ch +meta-char-specs+ :test (function char-equal))))

(defun decode-control-key (ch)
  (key-event-from-spec (char-code ch) +control-key-specs+))

(defun decode-character-key (ch &key vi-mode-p)
  (cond
    ((char= ch +escape+)
     (read-escape-key-event :vi-mode-p vi-mode-p))
    ((decode-control-key ch))
    ((printable-char-p ch) (make-key-event :char ch))
    (t (make-key-event :unknown ch))))
