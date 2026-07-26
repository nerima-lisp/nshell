; Static alist catalogs: builtin commands, external commands, and format specs.
(in-package #:nshell.domain.completion)

(defparameter +builtin-command-catalog+
  (%command-catalog
   (list
   (list :command "echo"
         :synopsis "echo [string ...]"
         :description "print arguments")
   (list :command "pwd"
         :synopsis "pwd"
         :description "print working directory")
   (list :command "ls"
         :synopsis "ls"
         :description "list directory contents"
         :flags '("-l" "-a" "-h" "-R" "--help"))
   (list :command "cd"
         :synopsis "cd [dir]"
         :description "change directory")
   (list :command "exit"
         :synopsis "exit"
         :description "exit the shell")
   (list :command "fg"
         :synopsis "fg [job-id]"
         :description "bring job to foreground")
   (list :command "bg"
         :synopsis "bg [job-id]"
         :description "resume job in background")
   (list :command "jobs"
         :synopsis "jobs"
         :description "list jobs")
   (list :command "disown"
         :synopsis "disown [job-id]"
         :description "remove job from job list")
   (list :command "set"
         :synopsis
         "set [-x|--export] name value... | set [-e|--erase] name... | set [-q|--query] name..."
         :description "manage variables"
         :flags '("-x" "--export" "-e" "--erase" "-q" "--query"))
   (list :command "export"
         :synopsis "export name"
         :description "export variable to environment")
   (list :command "alias"
         :synopsis "alias [name expansion...] | alias -e name... | alias -q name..."
         :description "manage aliases"
         :flags '("-e" "-q"))
   (list :command "abbr"
         :synopsis
         "abbr [-a [-p command|anywhere] name expansion...] [-e name...] [-q name...] [-l] [-s]"
         :description "manage abbreviations"
         :flags '("-a" "--add" "-p" "--position" "command" "anywhere"
                  "-e" "--erase" "-q" "--query" "-l" "--list" "-s" "--show"))
   (list :command "complete"
         ;; Assembled: longer than 100 columns, and a string literal cannot be
         ;; split across source lines without changing its value.
         :synopsis (concatenate 'string
                                "complete -c command [-f flag ...] [-l option ...]"
                                " [-s option ...] [-a arguments] [-d description] [-e]")
         :description "define completions"
         :flags '("-c" "--command" "-f" "--flag" "-l" "--long-option"
                  "-s" "--short-option" "-a" "--arguments" "-d" "--description"
                  "-e" "--erase"))
   (list :command "type"
         :synopsis "type [OPTIONS] NAME [...]"
         :description "show command type"
         :flags '("-a" "--all" "-s" "--short" "-f" "--no-functions"
                  "--color" "-q" "--query" "--quiet" "-p" "--path" "-P" "--force-path"
                  "-t" "--type" "-h" "--help")
         :option-values '(("--color" "always" "auto")))
   (list :command "which"
         :synopsis "which NAME [...]"
         :description "show command path")
   (list :command "test"
         :synopsis "test expression"
         :description "evaluate conditional")
   (list :command "["
         :synopsis "[ expression ]"
         :description "evaluate conditional")
   (list :command "string"
         ;; Assembled: longer than 100 columns, and a string literal cannot be
         ;; split across source lines without changing its value.
         :synopsis (concatenate 'string
                                "string collect|length|lower|upper|join|split"
                                "|replace|match|repeat|sub|trim ...;"
                                " string replace|match|repeat|sub|trim ...")
         :description "manipulate strings"
         :flags '("collect" "length" "lower" "upper" "join" "split" "replace"
                  "match" "repeat" "sub" "trim" "-a" "--all" "-q" "--quiet"
                  "-i" "--ignore-case" "--allow-empty" "-N" "--no-newline"
                  "-n" "--count" "-m" "--max" "-s" "--start" "-l" "--length"
                  "-e" "--end" "--"))
   (list :command "source"
         :synopsis "source file"
         :description "execute commands from file")
   (list :command "."
         :synopsis ". file"
         :description "execute commands from file")
   (list :command "read"
         :synopsis "read [-p prompt] variable"
         :description "read line of input"
         :flags '("-p"))
   (list :command "function"
         :synopsis "function [name body... end] | function -e name... | function -q name..."
         :description "manage functions"
         :flags '("-e" "-q"))
   (list :command "history"
         ;; Assembled: longer than 100 columns, and a string literal cannot be
         ;; split across source lines without changing its value.
         :synopsis (concatenate 'string
                                "history [search"
                                " [--prefix|--contains|--exact|--case-sensitive] query"
                                " | delete command | clear | size]")
         :description "show and manage command history"
         :flags '("search" "delete" "clear" "size" "--prefix" "--contains" "--exact"
                  "--case-sensitive"))
   (list :command "help"
         :synopsis "help [command]"
         :description "show help")
   (list :command "exec"
         :synopsis "exec command [args...]"
         :description "replace shell with command")
   (list :command "true"
         :synopsis "true"
         :description "return success")
   (list :command "false"
         :synopsis "false"
         :description "return failure")
   (list :command "contains"
         :synopsis "contains [-i|--index] string [values...]"
         :description "test whether a value is present"
         :flags '("-i" "--index" "--"))
   (list :command "count"
         :synopsis "count [values...]"
         :description "print the number of arguments"
         :flags '())
   (list :command "seq"
         :synopsis "seq [FIRST [STEP]] LAST"
         :description "print a sequence of integers"
         :flags '())
   (list :command "not"
         :synopsis "not command [args...]"
         :description "invert command status"))))

(defparameter +external-command-catalog+
  (%command-catalog
   (list
   (list :command "git"
         :description "distributed version control"
         :subcommands '((:name "add" :description "stage changes")
                        "branch"
                        (:name "checkout" :description "switch branches or restore paths")
                        "clone"
                        (:name "commit" :description "record changes")
                        "diff" "fetch" "log" "merge" "pull" "push" "rebase"
                        "restore"
                        (:name "status" :description "show working tree status")
                        "switch" "tag")
         :flags '("-C" "-c" "--help" "--version" "--no-pager" "--paginate"))
   (list :command "docker"
         :description "manage containers and images"
         :subcommands '("build" "compose" "exec" "images" "logs" "ps" "pull"
                        "push" "run" "stop")
         :flags '("--config" "--context" "--debug" "--help" "--host" "--log-level"
                  "--tls" "--tlscacert" "--tlscert" "--tlskey" "--version")
         :option-values '(("--log-level" "debug" "info" "warn" "error" "fatal")))
   (list :command "kubectl"
         :description "control Kubernetes clusters"
         :subcommands '("apply" "config" "create" "delete" "describe" "exec" "get"
                        "logs" "patch" "port-forward" "rollout" "scale")
         :flags '("--all-namespaces" "--context" "--help" "--kubeconfig"
                  "--namespace" "-n" "--output" "-o")
         :option-values '(("--output" "json" "yaml" "wide" "name")
                          ("-o" "json" "yaml" "wide" "name"))
         :exclusive-options '(("--all-namespaces" "--namespace" "-n")))
   (list :command "nix"
         :description "Nix package manager"
         :subcommands '("build" "develop" "flake" "fmt" "profile" "repl" "run"
                        "search" "shell" "store")
         :flags '("--accept-flake-config" "--extra-experimental-features" "--help"
                  "--impure" "--print-build-logs" "-L" "--version"))
   (list :command "cargo"
         :description "Rust package manager"
         :subcommands '("build" "check" "clean" "clippy" "doc" "fmt" "run" "test"
                        "update")
         :flags '("--color" "--help" "--manifest-path" "--offline" "--quiet" "-q"
                  "--verbose" "-v" "--version")
         :option-values '(("--color" "auto" "always" "never"))
         :exclusive-options '(("--quiet" "-q" "--verbose" "-v")))
   (list :command "npm"
         :description "JavaScript package manager"
         :subcommands '("ci" "install" "link" "publish" "run" "test" "update"
                        "version")
         :flags '("--help" "--global" "-g" "--prefix" "--silent" "--verbose"
                  "--version"))
   (list :command "gh"
         :description "GitHub command line interface"
         :subcommands '("api" "auth" "browse" "gist" "issue" "pr" "release"
                        "repo" "run" "secret" "workflow")
         :flags '("--help" "--hostname" "--repo" "-R" "--version"))
   (list :command "go"
         :description "Go toolchain"
         :subcommands '("build" "clean" "doc" "env" "fmt" "generate" "get"
                        "install" "list" "mod" "run" "test" "tool" "version"
                        "vet" "work")
         :flags '("-C" "-mod" "-modfile" "-overlay" "-p" "-race" "-tags"
                  "-v" "-x" "--help")
         :option-values '(("-mod" "mod" "readonly" "vendor")))
   (list :command "python"
         :description "Python interpreter"
         :flags '("-B" "-E" "-I" "-O" "-OO" "-S" "-V" "-W" "-c" "-m" "-q"
                  "--help" "--version"))
   (list :command "pip"
         :description "Python package installer"
         :subcommands '("cache" "check" "config" "download" "freeze" "install"
                        "list" "show" "uninstall" "wheel")
         :flags '("--help" "--isolated" "--no-cache-dir" "--proxy" "--quiet"
                  "-q" "--require-virtualenv" "--verbose" "-v" "--version"))
   (list :command "make"
         :description "build automation tool"
         :flags '("-B" "-C" "-f" "-j" "-k" "-n" "-s" "--always-make"
                  "--directory" "--dry-run" "--file" "--help" "--jobs"
                  "--keep-going" "--silent"))
   (list :command "curl"
         :description "transfer data with URLs"
         :flags '("-d" "--data" "-f" "--fail" "-H" "--header" "-I" "--head"
                  "-L" "--location" "-o" "--output" "-O" "--remote-name"
                  "-s" "--silent" "-u" "--user" "-v" "--verbose" "-X"
                  "--request" "--compressed" "--connect-timeout" "--help")
         :option-values '(("--request" "GET" "POST" "PUT" "PATCH" "DELETE" "HEAD")
                          ("-X" "GET" "POST" "PUT" "PATCH" "DELETE" "HEAD")))
   (list :command "jq"
         :description "command-line JSON processor"
         :flags '("-c" "--compact-output" "-r" "--raw-output" "-e"
                  "--exit-status" "-n" "--null-input" "-s" "--slurp" "-C"
                  "--color-output" "-M" "--monochrome-output" "--arg"
                  "--argjson" "--help"))
   (list :command "rg"
         :description "ripgrep search tool"
         :flags '("-F" "--fixed-strings" "-g" "--glob" "-i" "--ignore-case"
                  "-n" "--line-number" "-S" "--smart-case" "-t" "--type"
                  "-T" "--type-not" "--color" "--files" "--hidden" "--json"
                  "--help")
         :option-values '(("--color" "auto" "always" "never" "ansi")))
   (list :command "grep"
         :description "search text by pattern"
         :flags '("-E" "-F" "-H" "-I" "-R" "-i" "-n" "-q" "-r" "-v" "--color"
                  "--exclude" "--exclude-dir" "--help")
         :option-values '(("--color" "auto" "always" "never"))
         :exclusive-options '(("-E" "-F")))
   (list :command "find"
         :description "walk files matching expressions"
         :flags '("-L" "-H" "-P" "-name" "-iname" "-type" "-maxdepth" "-mindepth"
                  "-print" "-exec" "-delete"))
   (list :command "tar"
         :description "archive files"
         :flags '("-c" "-x" "-t" "-f" "-v" "-z" "-j" "-J" "--create" "--extract"
                  "--file" "--gzip" "--help"))
   (list :command "ssh"
         :description "OpenSSH remote login"
         :flags '("-A" "-F" "-J" "-L" "-N" "-R" "-T" "-V" "-i" "-l" "-p" "-v")))))

(defparameter +command-path-builtin-specs+
  '(("type"
     :builtin-format "~a is a shell builtin~%"
     :path-format "~a is ~a~%"
     :missing-prefix "type"
     :missing-format "~a: not found~%"
     :usage "type [OPTIONS] NAME [...]")
    ("which"
     :builtin-format "~a: shell built-in command~%"
     :path-format "~a~%"
     :missing-prefix "which"
     :missing-format "no ~a in PATH"
     :usage "which NAME [NAME ...]")))

(defparameter +type-builtin-spec+
  '(:alias-format "~a is an alias for ~a~%"
    :function-format "~a is a function~%"
    :abbreviation-format "~a is an abbreviation for ~a~%"
    :builtin-format "~a is a shell builtin~%"
    :path-builtin-format "~a is a builtin~%"
    :path-format "~a is ~a~%"
    :path-only-format "~a~%"
    :missing-format "~a: not found~%"
    :usage "type [OPTIONS] NAME [...]"))
