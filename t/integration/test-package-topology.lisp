(in-package #:nshell/test)

(defun %package-path (root relative-path)
  (merge-pathnames relative-path root))

(defun %package-directory-present-p (root relative-path)
  (probe-file (%package-path root relative-path)))

(describe "package-by-feature filesystem topology"
  (it "keeps the src DDD composition route present"
    (let ((root (asdf:system-source-directory :nshell)))
      (dolist (layer '("src/domain/"
                       "src/application/"
                       "src/infrastructure/"
                       "src/presentation/"))
        (expect (%package-directory-present-p root layer) :to-be-truthy))))

  (it "stores the command-line vertical slice under packages/feature"
    (let ((root (asdf:system-source-directory :nshell)))
      (dolist (layer '("packages/feature/command-line/src/domain/"
                       "packages/feature/command-line/src/application/"
                       "packages/feature/command-line/src/infrastructure/"
                       "packages/feature/command-line/src/presentation/"))
        (expect (%package-directory-present-p root layer) :to-be-truthy))))

  (it "keeps all three requested test tiers addressable"
    (let ((root (asdf:system-source-directory :nshell)))
      (dolist (tier '("t/unit/" "t/integration/" "t/e2e/"))
        (expect (%package-directory-present-p root tier) :to-be-truthy)))))
