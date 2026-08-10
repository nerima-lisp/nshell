(in-package #:nshell/test)

(describe "package-by-feature topology"
  (it "registers the command-line feature with all DDD layers"
    (let ((feature (nshell.architecture:find-feature :command-line)))
      (expect (nshell.architecture:feature-descriptor-p feature)
              :to-be-truthy)
      (expect :command-line :to-equal
              (nshell.architecture:feature-descriptor-name feature))
      (expect "packages/feature/command-line/src" :to-equal
              (nshell.architecture:feature-descriptor-root feature))
      (expect '(:domain :application :infrastructure :presentation) :to-equal
              (nshell.architecture:feature-descriptor-layers feature))
      (expect "packages/feature/command-line/src/domain" :to-equal
              (nshell.architecture:feature-layer-path feature :domain))
      (expect "packages/feature/command-line/src/presentation" :to-equal
              (nshell.architecture:feature-layer-path :command-line
                                                      :presentation))))

  (it "keeps command-line policy independent from the parser implementation"
    (expect (nshell.feature.command-line:flag-argument-p "--help")
            :to-be-truthy)
    (expect (nshell.feature.command-line:flag-argument-p "script.nsh")
            :to-be-falsy)
    (expect "Usage: nshell [OPTIONS] [-c COMMAND [ARGS...]] [SCRIPT [ARGS...]]"
            :to-equal
            (nshell.feature.command-line:usage-synopsis))))
