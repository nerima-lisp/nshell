(in-package #:nshell/test)

(describe "sexp-reader-prototype-execution-tests"
          (it
           "executes-prototype-generated-command-nodes-through-the-public-pipeline-api"
           (let* ((true-node
                   (nshell.domain.parsing::parse-sexp-reader-prototype "(true)"))
                  (printf-node
                   (nshell.domain.parsing::parse-sexp-reader-prototype
                    "printf %s pipeline-api"))
                  (true-code
                   (nshell.application:execute-pipeline-use-case true-node))
                  (printf-code nil)
                  (output
                   (with-output-to-string (*standard-output*)
                     (setf printf-code (nshell.application:execute-pipeline-use-case
                                        printf-node)))))
             (expect 0 :to-equal true-code)
             (expect 0 :to-equal printf-code)
             (expect "pipeline-api" :to-equal output)))
          (it "executes-prototype-generated-pipeline-nodes-through-the-public-api"
              (let* ((node
                      (nshell.domain.parsing::parse-sexp-reader-prototype
                       "(| (printf %s pipeline-api) (cat))"))
                     (code nil)
                     (output
                      (with-output-to-string (*standard-output*)
                        (setf code
                              (nshell.application:execute-pipeline-use-case
                               node)))))
                (expect 0 :to-equal code)
                (expect "pipeline-api" :to-equal output)))
          (it "merges-stderr-through-the-public-pipeline-api-for-bare-pipe-ampersand"
              (let* ((node
                      (nshell.domain.parsing::parse-sexp-reader-prototype
                       "sh -c 'printf error >&2' |& cat"))
                     (code nil)
                     (output
                      (with-output-to-string (*standard-output*)
                        (setf code
                              (nshell.application:execute-pipeline-use-case
                               node)))))
                (expect 0 :to-equal code)
                (expect "error" :to-equal output)))
          (it "executes-a-quoted-bare-line-argument-as-one-literal-value"
              (let* ((node
                      (nshell.domain.parsing::parse-sexp-reader-prototype
                       "printf '%s' \"two words\""))
                     (code nil)
                     (output
                      (with-output-to-string (*standard-output*)
                        (setf code
                              (nshell.application:execute-pipeline-use-case
                               node)))))
                (expect 0 :to-equal code)
                (expect "two words" :to-equal output))))
