#!/usr/bin/env nshell
# Example nshell script. Run it with:
#   nshell examples/greet.nsh World
#
# Demonstrates a function, $argv, a test in an S-expression, and a loop.

;; A function defined with defun; NAME is its argument.
(defun greet (name)
  (echo ,(concatenate (quote string) "Hello, " name "!")))

;; $argv[1] is the first argument; fall back to a default when it is empty.
(set name $argv[1])
(when (test -z $name)
  (set name world))

greet $name

echo "Arguments:" $argv

echo "Counting to five:"
(dotimes (i 5)
  (echo ,(format NIL "  ~d" (1+ i))))
