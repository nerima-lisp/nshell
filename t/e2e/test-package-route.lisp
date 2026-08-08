(in-package #:nshell/test)

(describe "package-by-feature composition route"
  (it "routes the legacy src entry points to the feature presentation"
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

  (it "keeps the feature parser reachable through src/main"
    (let ((feature
            (cl-cli:parse-argv
             (nshell.feature.command-line:build-cli-app)
             '("nshell" "--version")))
          (root
            (cl-cli:parse-argv
             (nshell::%build-cli-app)
             '("nshell" "--version"))))
      (expect (cl-cli:option-value feature :show-version) :to-be-truthy)
      (expect (cl-cli:option-value root :show-version) :to-be-truthy))))
