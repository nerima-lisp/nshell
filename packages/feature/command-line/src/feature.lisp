(in-package #:nshell.feature.command-line)

(eval-when (:load-toplevel :execute)
  (nshell.architecture:register-feature
   :command-line
   :root "packages/feature/command-line/src"
   :layers '(:domain :application :infrastructure :presentation)))
