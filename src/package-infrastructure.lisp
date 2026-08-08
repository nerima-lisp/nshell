;;; nshell infrastructure package definitions -- see package.lisp for the split's rationale.

(eval-when (:compile-toplevel :load-toplevel :execute)
;; -- Infrastructure packages --------------------------------
(defpackage #:nshell.infrastructure.acl
  (:documentation
   "Infrastructure: the anti-corruption layer over the operating system. Every
sb-posix call the shell makes -- fork and exec, pipes, redirection, process
groups, waitpid, PTYs, signal handlers -- is behind this one package, plus the
git subprocess the prompt needs. Its exports are the ports the application layer
stores in the shell context, which is what makes the layers above it mockable.")
  (:use #:cl)
  (:import-from #:nshell.util #:define-value-struct)
  (:export #:*exported-environment*
           #:spawn-pipeline #:spawn-pipeline-async #:wait-job
           #:spawn-process-substitution
           #:process-substitution-resource-p
           #:process-substitution-resource-path
           #:process-substitution-resource-fd
           #:release-process-substitution-fd
           #:wait-process-substitution
           #:close-process-substitution
            #:spawn-async
            #:kill-process #:os-signal->domain
            #:redirect-output #:redirect-error #:redirect-output-and-error
            #:redirect-output-to-error
            #:redirect-error-to-output
            #:redirect-input #:redirect-input-document #:redirect-input-string
           #:restore-redirects #:domain-signal->os
            #:install-signal-handlers #:consume-children-changed-p
            #:consume-terminal-resize-p
            #:open-pty #:with-pty #:pty-read #:pty-write #:pty-close #:make-pty-stream
            #:pty-spawn #:pty-process #:pty-process-p #:pty-process-pid
            #:pty-process-pgid #:pty-process-master-fd #:pty-process-stream
            #:set-process-group #:set-foreground-pgroup #:get-foreground-pgroup
            #:child-status #:child-status-p #:child-status-pid #:child-status-status
            #:reap-children #:get-terminal-size
            #:terminal-size-unavailable #:terminal-size-unavailable-fd
            #:*external-command-timeout*
            #:run-external #:run-external-capture #:run-external-exec
            #:process-exit-status-code
            #:with-git-runner #:clear-git-status-cache
            #:get-git-status))

(defpackage #:nshell.infrastructure.terminal
  (:documentation
   "Infrastructure: the terminal device. Puts the tty into raw mode and restores
it, emits the ANSI sequences for cursor, colour, alternate screen, bracketed
paste, and SGR mouse, and decodes incoming bytes -- including escape sequences --
into the key events defined by nshell.domain.input, which it re-exports so the
line editor has a single place to import them from.")
  (:use #:cl)
  (:import-from #:nshell.domain.input
                #:key-event #:key-event-p #:make-key-event
                #:key-event-type #:key-event-char #:key-event-number
                #:key-event-data)
  (:export #:enable-raw-mode #:restore-terminal-mode
            #:terminal-mode-operation-failed
            #:terminal-mode-operation-failed-operation
            #:terminal-mode-operation-failed-fd
            #:terminal-mode-operation-failed-reason
            #:ansi-clear-screen #:ansi-clear-line #:ansi-move-cursor
            #:ansi-color-code
            #:ansi-cursor-up #:ansi-cursor-down
            #:ansi-cursor-forward #:ansi-cursor-back #:ansi-cursor-column
            #:ansi-dim #:ansi-reverse #:ansi-reset-style
            #:ansi-save-cursor #:ansi-restore-cursor
            #:ansi-hide-cursor #:ansi-show-cursor
            #:ansi-enable-bracketed-paste #:ansi-disable-bracketed-paste
            #:ansi-enable-sgr-mouse #:ansi-disable-sgr-mouse
            #:ansi-enable-alternate-screen #:ansi-disable-alternate-screen
            #:ansi-request-cursor-position
            #:ansi-copy-to-clipboard
            #:copy-to-clipboard
            #:read-key-event
            #:query-cursor-position
            #:key-event #:key-event-p #:make-key-event
            #:key-event-type #:key-event-char #:key-event-number
            #:key-event-data))

(defpackage #:nshell.infrastructure.persistence
  (:documentation
   "Infrastructure: state that outlives a session. Locates, reads, and appends
to the history file as plain text lines (the caller wraps them into
history-kit entries) and loads and saves the config file, converting
between that on-disk format and nshell.domain.configuration's domain
values.")
  (:use #:cl)
  (:export #:*history-file-path-override*
           #:load-history-file #:append-history-entry
           #:history-file-path
           #:load-config #:save-config))
)
