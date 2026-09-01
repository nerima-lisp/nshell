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
                                                       :presentation)))

  (it "keeps command-line policy independent from the parser implementation"
    (expect (nshell.feature.command-line:flag-argument-p "--help")
            :to-be-truthy)
    (expect (nshell.feature.command-line:flag-argument-p "script.nsh")
            :to-be-falsy)
    (expect "Usage: nshell [OPTIONS] [-c COMMAND [ARGS...]] [SCRIPT [ARGS...]]"
             :to-equal
             (nshell.feature.command-line:usage-synopsis)))

  (it "rejects empty and non-string flag arguments"
    (expect (nshell.feature.command-line:flag-argument-p "")
            :to-be-falsy)
    (expect (nshell.feature.command-line:flag-argument-p 42)
            :to-be-falsy))

  (it "orders the registered descriptors by name"
    (let ((first (nshell.architecture:register-feature
                  :aaa :root "a" :layers '(:domain)))
          (second (nshell.architecture:register-feature
                   :zzz :root "z" :layers '(:application))))
      (declare (ignore first second))
      (unwind-protect
           (expect '(:aaa :command-line :zzz) :to-equal
                   (mapcar #'nshell.architecture:feature-descriptor-name
                           (nshell.architecture:all-features)))
        (remhash :aaa nshell.architecture::*feature-registry*)
        (remhash :zzz nshell.architecture::*feature-registry*))))

  (it "replaces descriptors and rejects invalid layers"
    (nshell.architecture:register-feature
     :temporary :root "old" :layers '(:domain))
    (unwind-protect
         (progn
           (nshell.architecture:register-feature
            :temporary :root "new" :layers '(:application))
           (expect "new" :to-equal
                   (nshell.architecture:feature-descriptor-root
                    (nshell.architecture:find-feature :temporary)))
           (expect (handler-case
                       (progn
                         (nshell.architecture:feature-layer-path
                          :temporary :domain)
                         nil)
                     (error () t))
                   :to-be-truthy))
      (remhash :temporary nshell.architecture::*feature-registry*)))

  (it "rejects unknown features and malformed registrations"
    (expect (handler-case
                (progn (nshell.architecture:feature-layer-path :missing :domain)
                       nil)
              (error () t))
            :to-be-truthy)
    (expect (handler-case
                (progn (nshell.architecture:register-feature
                        "not-a-keyword" :root "x" :layers nil)
                       nil)
              (error () t))
            :to-be-truthy)
    (expect (handler-case
                (progn (nshell.architecture:register-feature
                        :bad-root :root 42 :layers nil)
                       nil)
              (error () t))
            :to-be-truthy)
    (expect (handler-case
                (progn (nshell.architecture:register-feature
                        :bad-layer :root "x" :layers '(domain))
                       nil)
              (error () t))
              :to-be-truthy))))

  (it "accepts descriptors directly and validates requested layers"
    (let ((feature (nshell.architecture:register-feature
                    :direct :root "direct" :layers '(:domain))))
      (unwind-protect
           (progn
             (expect "direct/domain" :to-equal
                     (nshell.architecture:feature-layer-path feature :domain))
             (expect (handler-case
                         (progn
                           (nshell.architecture:feature-layer-path feature "domain")
                           nil)
                       (error () t))
                     :to-be-truthy))
        (remhash :direct nshell.architecture::*feature-registry*))))

  (it "supports empty feature registries and descriptor mutation"
    (let ((feature (nshell.architecture:register-feature
                    :empty :root "empty" :layers nil)))
      (unwind-protect
           (progn
             (expect nil :to-equal
                     (nshell.architecture:feature-descriptor-layers feature))
             (expect (member :command-line
                             (mapcar #'nshell.architecture:feature-descriptor-name
                                     (nshell.architecture:all-features)))
                     :to-be-truthy)
             (setf (nshell.architecture:feature-descriptor-layers feature)
                   '(:domain))
             (expect '(:domain) :to-equal
                     (nshell.architecture:feature-descriptor-layers feature)))
        (remhash :empty nshell.architecture::*feature-registry*))))
