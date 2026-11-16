(in-package #:cl-user)

(defpackage #:nshell/spec
  (:use #:cl)
  (:import-from #:cl-weave #:it #:it-fails #:expect #:run-all)
  (:export #:register-language-probes #:run))
