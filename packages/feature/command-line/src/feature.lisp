(in-package #:nshell.feature.command-line)

(nshell.architecture:define-feature
 :command-line
 :root "packages/feature/command-line/src"
 :layers (:domain :application :infrastructure :presentation))
