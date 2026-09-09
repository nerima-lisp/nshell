(in-package #:nshell.feature.assistant)

(nshell.architecture:define-feature
 :assistant
 :root "packages/feature/assistant/src"
 :layers (:domain :application :infrastructure :presentation))
