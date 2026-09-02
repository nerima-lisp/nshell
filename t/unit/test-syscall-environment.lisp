(in-package #:nshell/test)

(describe "syscall-environment"
  (it "reads the process environment and working directory"
    (let ((entries (nshell.infrastructure.acl:current-environment-entries)))
      (expect entries :to-be-truthy)
      (expect (some (lambda (entry)
                      (and (stringp entry)
                           (find #\= entry)))
                    entries)
              :to-be-truthy))
    (expect (or (stringp (nshell.infrastructure.acl:current-working-directory))
                (pathnamep (nshell.infrastructure.acl:current-working-directory)))
            :to-be-truthy))

  (it "reads a named process environment value"
    (expect (stringp
             (nshell.infrastructure.acl:current-environment-value "PATH"))
            :to-be-truthy))

  (it "prefers explicitly exported environment entries"
    (let ((nshell.infrastructure.acl:*exported-environment*
            '("NSHELL_TEST_VALUE=explicit")))
      (expect nshell.infrastructure.acl:*exported-environment*
              :to-equal
              (nshell.infrastructure.acl::%get-environment)))))
