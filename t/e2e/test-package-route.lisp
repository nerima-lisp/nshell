(in-package #:nshell/test)

(describe "package-by-feature composition route"
  (it "routes the composition root to the feature presentation"
    (let ((feature-usage
            (with-output-to-string (stream)
              (nshell.feature.command-line:print-usage stream)))
          (root-usage
            (with-output-to-string (stream)
              (nshell::%print-usage stream)))
          (feature-version
            (with-output-to-string (stream)
              (nshell.feature.command-line:print-version stream)))
          (root-version
            (with-output-to-string (stream)
              (nshell::%print-version stream))))
      (expect feature-usage :to-equal root-usage)
      (expect feature-version :to-equal root-version)))

  (it "keeps the executable parser at the composition root"
    (let ((invocation
            (nth-value 0
                       (nshell::%parse-cli-arguments '("--version")))))
      (expect (cl-cli:option-value invocation :show-version)
              :to-be-truthy))))
