(in-package #:nshell/test)

(describe "builtin-tests"
  (it "pbt-string-match-ignore-case-matches-generated-words"
    "string match -i agrees with case-insensitive equality for generated shell words."
    (assert-string-builtin-property (context)
        ((word (gen-shell-word :min-length 1 :max-length 8)))
      (let ((candidate (string-upcase word)))
        (multiple-value-bind (output code)
            (call-string-builtin context
                          (list "match" "-i" "--" word candidate))
          (and (= code 0)
               (string= (format nil "~A~%" candidate) output))))))

  (it "pbt-string-replace-ignore-case-replaces-generated-words"
    "string replace -i replaces generated shell words regardless of case."
    (assert-string-builtin-property (context)
        ((word (gen-shell-word :min-length 1 :max-length 8)))
      (let ((candidate (string-upcase word)))
        (multiple-value-bind (output code)
            (call-string-builtin context
                          (list "replace" "-i" "--" word "X" candidate))
          (and (= code 0)
               (string= (format nil "X~%") output))))))

  (it "pbt-string-repeat-count-controls-generated-output-length"
    "string repeat -n produces count copies for generated shell words."
    (assert-string-builtin-property (context)
        ((word (gen-shell-word :min-length 1 :max-length 6))
         (count (gen-in-range 1 6)))
      (multiple-value-bind (output code)
          (call-string-builtin context
                        (list "repeat" "-n" (write-to-string count) "--" word))
        (and (= code 0)
             (= (length output)
                (1+ (* (length word) count)))))))

  (it "pbt-string-repeat-max-bounds-generated-output-length"
    "string repeat -m caps generated output before the trailing newline."
    (assert-string-builtin-property (context)
        ((word (gen-shell-word :min-length 1 :max-length 6))
         (max (gen-in-range 1 12)))
      (multiple-value-bind (output code)
          (call-string-builtin context
                        (list "repeat" "-m" (write-to-string max) "--" word))
        (and (= code 0)
             (= (length output) (1+ max))))))

  (it "pbt-string-collect-default-trims-generated-trailing-newlines"
    "string collect trims generated trailing newlines by default."
    (expect (assert-string-builtin-property (context)
         ((word (gen-shell-word :min-length 1 :max-length 10))
          (newline-count (gen-in-range 1 4)))
       (let ((input (concatenate 'string
                                  word
                                  (make-string newline-count
                                               :initial-element #\Newline))))
         (multiple-value-bind (output code)
             (call-string-builtin context (list "collect" "--" input))
           (and (= code 0)
                (string= (format nil "~A~%" word) output))))) :to-be-truthy))

  (it "pbt-string-sub-positive-start-and-length-control-output-length"
    "string sub -s/-l returns the generated positive-index slice length."
    (expect (assert-string-builtin-property (context)
         ((word (gen-shell-word :min-length 1 :max-length 12))
          (start (gen-in-range 1 12))
          (requested-length (gen-in-range 1 12)))
       (let* ((expected-length
                (min requested-length
                     (max 0 (- (length word) (1- start)))))
              (expected-code (if (plusp (length word)) 0 1)))
         (multiple-value-bind (output code)
             (call-string-builtin context
                           (list "sub" "-s" (write-to-string start)
                                 "-l" (write-to-string requested-length)
                                 "--" word))
           (and (= code expected-code)
                (= (length output) (1+ expected-length)))))) :to-be-truthy)))
