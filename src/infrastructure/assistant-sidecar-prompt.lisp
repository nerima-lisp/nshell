(in-package #:nshell.feature.assistant)

(defparameter *assistant-sidecar-system-prompt*
  "Return exactly one JSON object with string keys command, reason, and risk. Do not include prose outside that object.")

(defparameter *assistant-sidecar-json-schema*
  "{\"type\":\"object\",\"properties\":{\"command\":{\"type\":\"string\"},\"reason\":{\"type\":\"string\"},\"risk\":{\"type\":\"string\"}},\"required\":[\"command\",\"reason\",\"risk\"],\"additionalProperties\":false}")

(defun assistant-sidecar-system-prompt ()
  *assistant-sidecar-system-prompt*)

(defun assistant-sidecar-json-schema ()
  *assistant-sidecar-json-schema*)
