(in-package #:nshell/test)

(defun %trampoline-result-sequence (sequence)
  (let ((results '()))
    (labels ((next-continuation (remaining)
               (when remaining
                 (lambda ()
                   (push (first remaining) results)
                   (next-continuation (rest remaining))))))
      (nshell.presentation:trampoline
       (lambda ()
         (next-continuation sequence))))
    results))

(defmacro assert-trampoline-sequence (expected values)
  `(expect ,expected :to-equal (%trampoline-result-sequence ,values)))

(describe "cps-tests"
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
    (assert-trampoline-sequence nil nil))

  (it "with-cps-trampoline-runs-the-initial-step"
    (let ((steps '()))
      (nshell.presentation:with-cps-trampoline
        (push :initial steps)
        (lambda ()
          (push :continuation steps)
          nil))
      (expect '(:continuation :initial) :to-equal steps))))
