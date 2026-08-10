(in-package #:nshell.domain.completion)

(defparameter +external-subcommand-completion-specs+
  '(("git status"
     :flags ("--branch" "--porcelain" "--short" "--untracked-files"))
    ("git diff"
     :flags ("--cached" "--check" "--name-only" "--stat" "--staged" "--word-diff"))
    ("git commit"
     :flags ("--all" "--amend" "--message" "--no-edit" "-a" "-m"))
    ("git checkout"
     :flags ("--detach" "--force" "--orphan" "-b" "-B"))
    ("git log"
     :flags ("--all" "--author" "--graph" "--oneline" "--reverse" "-n"))
    ("git pull"
     :flags ("--ff-only" "--no-rebase" "--rebase" "--tags" "--unshallow"))
    ("git push"
     :flags ("--all" "--delete" "--force" "--force-with-lease" "--set-upstream" "-u"))
    ("docker compose"
     :subcommands ("build" "down" "exec" "logs" "ps" "run" "up"))
    ("docker compose up"
     :flags ("--build" "--detach" "--force-recreate" "--no-deps" "--remove-orphans"))
    ("docker run"
     :flags ("--detach" "--env" "--name" "--publish" "--rm" "--volume"))
    ("docker exec"
     :flags ("--detach" "--env" "--interactive" "--privileged" "--tty"))
    ("kubectl apply"
     :flags ("--all" "--dry-run" "--filename" "--namespace" "--prune" "--recursive" "-f" "-n"))
    ("kubectl get"
     :flags ("--all-namespaces" "--namespace" "--output" "--selector" "-n" "-o"))
    ("cargo build"
     :flags ("--all-features" "--bin" "--features" "--locked" "--release"))
    ("cargo test"
     :flags ("--all-features" "--doc" "--exact" "--features" "--no-run" "--release"))
    ("npm run"
     :flags ("--if-present" "--silent" "--workspace" "--workspaces"))
    ("gh pr"
     :flags ("--help" "--json" "--repo" "--web"))
    ("gh issue"
     :flags ("--assignee" "--label" "--repo" "--state" "--web"))
    ("go test"
     :flags ("-bench" "-count" "-cover" "-race" "-run" "-v"))))

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
