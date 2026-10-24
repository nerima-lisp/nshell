(in-package #:nshell/test)

(defun %trampoline-result-sequence (sequence)
  (let ((results '()))
    (labels ((next-continuation (remaining)
               (if remaining
                   (lambda ()
                     (push (first remaining) results)
                     (next-continuation (rest remaining)))
                   nshell.presentation::+repl-exit+)))
      (nshell.presentation:trampoline
       (lambda ()
         (next-continuation sequence))))
    results))

(defmacro assert-trampoline-sequence (expected values)
  `(expect ,expected :to-equal (%trampoline-result-sequence ,values)))

(describe "cps-tests"
  (it "with-cps-trampoline-expands-to-trampoline"
    (multiple-value-bind (expansion expanded-p)
        (macroexpand-1
         '(nshell.presentation:with-cps-trampoline
            (lambda () nshell.presentation::+repl-exit+)))
      (expect expanded-p :to-be-truthy)
      (expect 'nshell.presentation:trampoline :to-be (first expansion))))

  (it "trampoline-sequential"
    (assert-trampoline-sequence '(3 2 1) '(1 2 3)))

  (it "trampoline-stops-after-done"
    (assert-trampoline-sequence '(:start) '(:start)))

  (it "pbt-trampoline-preserves-continuation-order"
    (check-property (:trials 50)
        ((depth (gen-in-range 1 8) nil))
      (equal (reverse (loop for i from 1 to depth collect i))
             (%trampoline-result-sequence
              (loop for i from 1 to depth collect i)))))

  (it "trampoline-termination"
    (expect nshell.presentation::+repl-exit+ :to-equal
            (nshell.presentation:trampoline
             (lambda () nshell.presentation::+repl-exit+)))
    (assert-trampoline-sequence nil nil))

  (it "trampoline-recovers-from-nil-and-integer-results"
    (let ((calls 0)
          (diagnostic (make-string-output-stream)))
      (let ((*error-output* diagnostic))
        (expect nshell.presentation::+repl-exit+ :to-equal
                (nshell.presentation:trampoline
                 (lambda ()
                   (case (incf calls)
                     (1 nil)
                     (2 23)
                     (otherwise nshell.presentation::+repl-exit+))))))
      (expect 3 :to-equal calls)
      (expect 2 :to-equal
              (count #\Newline (get-output-stream-string diagnostic)))))

  (it "trampoline-restarts-the-initial-step-after-invalid-continuation"
    (let ((initial-calls 0)
          (continuation-calls 0)
          (diagnostic (make-string-output-stream)))
      (let ((*error-output* diagnostic))
        (expect nshell.presentation::+repl-exit+ :to-equal
                (nshell.presentation:trampoline
                 (lambda ()
                   (if (= (incf initial-calls) 1)
                       (lambda ()
                         (incf continuation-calls)
                         nil)
                       nshell.presentation::+repl-exit+)))))
      (expect 2 :to-equal initial-calls)
      (expect 1 :to-equal continuation-calls)
      (expect 1 :to-equal
              (count #\Newline (get-output-stream-string diagnostic)))))

  (it "with-cps-trampoline-runs-the-initial-step"
    (let ((steps '()))
      (expect nshell.presentation::+repl-exit+ :to-equal
              (nshell.presentation:with-cps-trampoline
                (push :initial steps)
                (lambda ()
                  (push :continuation steps)
                  nshell.presentation::+repl-exit+)))
      (expect '(:continuation :initial) :to-equal steps))))
