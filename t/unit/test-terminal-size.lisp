(in-package #:nshell/test)

(describe "terminal-width-tests"
  (it "returns the reported positive width"
    (with-temporary-function
        ('nshell.infrastructure.acl:get-terminal-size
         (lambda () (values 24 120)))
      (expect 120 :to-equal (nshell.presentation::terminal-width))))

  (it "uses the fallback width for a non-positive size"
    (with-temporary-function
        ('nshell.infrastructure.acl:get-terminal-size
         (lambda () (values 24 0)))
      (expect 80 :to-equal (nshell.presentation::terminal-width))))

  (it "uses the fallback width when the size query fails"
    (with-temporary-function
        ('nshell.infrastructure.acl:get-terminal-size
         (lambda () (error 'simple-error :format-control "no tty")))
      (expect 80 :to-equal (nshell.presentation::terminal-width)))))
