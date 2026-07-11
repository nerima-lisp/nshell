(in-package #:nshell/test)
(def-suite cps-tests :description "CPS trampoline tests" :in nshell-tests)
(in-suite cps-tests)

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
  `(is (equal ,expected (%trampoline-result-sequence ,values))))

(test trampoline-sequential
  (assert-trampoline-sequence '(3 2 1) '(1 2 3)))

(test trampoline-stops-after-done
  (assert-trampoline-sequence '(:start) '(:start)))

(test pbt-trampoline-preserves-continuation-order
  (check-property (:trials 50)
      ((depth (gen-in-range 1 8) nil))
    (equal (reverse (loop for i from 1 to depth collect i))
           (%trampoline-result-sequence
            (loop for i from 1 to depth collect i)))))

(test trampoline-termination
  (assert-trampoline-sequence nil nil))
