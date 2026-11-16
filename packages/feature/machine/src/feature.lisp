(in-package #:nshell.feature.machine)

(nshell.architecture:define-feature
 :machine
 :root "packages/feature/machine/src"
 :layers (:domain :application))
