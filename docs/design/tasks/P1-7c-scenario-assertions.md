# P1-7c シナリオの assertion とテストの対応

[P1-7c-scenario-corpus.md](P1-7c-scenario-corpus.md) の付録です。[削除]・[削除 (先にテストを足す)] のシナリオと、見直しで [残す] に変えた 4 本については、assertion ごとに、それを確かめているテストのファイル・行・名前と、テストの本文のどこが対応するかを書いています。確かめているテストが「なし」の assertion は、本文の「削除の前に」のテストで確かめるか、[残す] のシナリオが PTY で確かめます。[golden へ移す] のシナリオについては、`t/golden/<id>.json` に置くケースを書いています。

[残す] のうち 37 本と、[削除 (F4)] の 1 本は、ここに載せていません。この 37 本は、PTY でしか確かめられない挙動があるので残すと判定したもので、assertion ごとの対応は確かめていません。残す理由は本文の表にあります。

### A01-terminal-launch

`t/scenarios/A01/approx-terminal-launch.json` [削除]

シナリオの入口: 実 PTY の対話 REPL (キー入力 → 行エディタ → 送信 → 実行 → 端末への出力、exit/Ctrl-D で終了)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "A01_TERMINAL_READY" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY で nshell main を対話起動し、行を PTY に書いて出力を読む (%call-with-job-pty → %e2e-pty-spawn) | はい | 実 PTY の対話 REPL に外部コマンドの行を打ち、その出力が端末出力に届くことを確かめる (terminal.txt の外部 cat の出力と同じ種類の値) |
| `expected.exit_code` | 0 | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY で nshell main を対話起動し、行を PTY に書いて出力を読む (%call-with-job-pty → %e2e-pty-spawn) | はい | 同じテストが最後に exit を書き、%assert-pty-child-exit で終了コード 0 を確かめる |
| `steps[2].contains` | "A01_TERMINAL_READY" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY で nshell main を対話起動し、行を PTY に書いて出力を読む (%call-with-job-pty → %e2e-pty-spawn) | はい | シナリオ自身の印を待つ同期。同じテストが外部コマンドの出力を待ってから exit に進む |

### A02-tmux-pane-start

`t/scenarios/A02/approx-tmux-pane-start.json` [削除]

シナリオの入口: 実 PTY の対話 REPL (キー入力 → 行エディタ → 送信 → 実行 → 端末への出力、exit/Ctrl-D で終了)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "A02_PANE_READY" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY で nshell main を対話起動し、行を PTY に書いて出力を読む (%call-with-job-pty → %e2e-pty-spawn) | はい | 実 PTY の対話 REPL に外部コマンドの行を打ち、その出力が端末出力に届くことを確かめる (pane.txt の外部 cat の出力と同じ種類の値) |
| `expected.exit_code` | 0 | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY で nshell main を対話起動し、行を PTY に書いて出力を読む (%call-with-job-pty → %e2e-pty-spawn) | はい | 同じテストが最後に exit を書き、%assert-pty-child-exit で終了コード 0 を確かめる |
| `steps[2].contains` | "A02_PANE_READY" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY で nshell main を対話起動し、行を PTY に書いて出力を読む (%call-with-job-pty → %e2e-pty-spawn) | はい | シナリオ自身の印を待つ同期。同じテストが外部コマンドの出力を待ってから exit に進む |

### A03-login-shell-command

`t/scenarios/A03/login-shell-command.json` [削除 (先にテストを足す)]

シナリオの入口: argv `-l -c printf 'A03_LOGIN_OK\n'` で nshell main を起動 (-c は /bin/sh に委譲)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stdout.equals` | "A03_LOGIN_OK\n" | `t/e2e/test-smoke-script.lisp:55` it "e2e-main-shell-command-delegates-with-argv-and-login-config" | argv `-c TEXT` (-l なし。別ケースで -ilc) で main をサブプロセス起動 (%run-nshell-main) | はい | -c の printf を /bin/sh に委譲し stdout の完全一致を確かめる。ただし argv に -l がなく、-l の後に -c を置いた argv を main に通すテストはない (-l の解析は `t/main-test.lisp:42` の unit だけ) |
| `expected.stderr.equals` | "" | `t/e2e/test-smoke-script.lisp:55` it "e2e-main-shell-command-delegates-with-argv-and-login-config" | argv `-c TEXT` (-l なし。別ケースで -ilc) で main をサブプロセス起動 (%run-nshell-main) | はい | 同じテストで -c 委譲の stderr "" を確かめる (-l なし) |
| `expected.exit_code` | 0 | `t/e2e/test-smoke-script.lisp:55` it "e2e-main-shell-command-delegates-with-argv-and-login-config" | argv `-c TEXT` (-l なし。別ケースで -ilc) で main をサブプロセス起動 (%run-nshell-main) | はい | 同じテストで -c 委譲の終了コード (37 と 0) を確かめる (-l なし) |

### A06-login-environment

`t/scenarios/A06/login-environment.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.contains[0]` | "A06_OK\|r04-user\|/r04-login-shell\|" | なし | e2e は -c に USER・SHELL・SHLVL を渡しておらず、環境変数が /bin/sh に引き継がれることを確かめるテストがない |
| `expected.stderr.equals` | "" | `t/e2e/test-smoke-script.lisp:55` it "e2e-main-shell-command-delegates-with-argv-and-login-config" | -c 委譲の stderr が "" であることを確かめる |
| `expected.exit_code` | 0 | なし | スクリプトは条件が外れると exit 91 になる。環境の引き継ぎを確かめるテストがないので、この 0 は対応しない |

### A07-quiet-login-command

`t/scenarios/A07/quiet-login-command.json` [削除 (先にテストを足す)]

シナリオの入口: argv `-l -c true` で nshell main を起動 (-c は /bin/sh に委譲)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stdout.equals` | "" | `t/e2e/test-smoke-script.lisp:55` it "e2e-main-shell-command-delegates-with-argv-and-login-config" | argv `-c TEXT` (-l なし。別ケースで -ilc) で main をサブプロセス起動 (%run-nshell-main) | はい | -c "" の stdout "" を確かめる。ただし argv に -l がなく、-l -c true を main に通すテストはない (-l の解析は `t/main-test.lisp:42` の unit だけ) |
| `expected.stderr.equals` | "" | `t/e2e/test-smoke-script.lisp:55` it "e2e-main-shell-command-delegates-with-argv-and-login-config" | argv `-c TEXT` (-l なし。別ケースで -ilc) で main をサブプロセス起動 (%run-nshell-main) | はい | -c "" の stderr "" を確かめる (-l なし) |
| `expected.exit_code` | 0 | `t/e2e/test-smoke-script.lisp:55` it "e2e-main-shell-command-delegates-with-argv-and-login-config" | argv `-c TEXT` (-l なし。別ケースで -ilc) で main をサブプロセス起動 (%run-nshell-main) | はい | -c "" の終了コード 0 を確かめる (-l なし) |

### WP-R10-whitespace-keeps-repl-alive

`t/scenarios/A08/WP-R10-whitespace-keeps-repl-alive.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "CPS_WS_ALIVE" | なし | 空白だけの行のあとに次のコマンドが動くことを確かめるテストはない。`t/unit/test-repl-execution.lisp:592` は buffer "" の :execute だけで、"   " も後続コマンドも試していない |
| `expected.stream.contains[1]` | "Goodbye!" | なし | Goodbye! を確かめるのは `t/unit/test-repl.lisp:411` だけで、端末設定に失敗して exit 1 で終わる経路。exit コマンドで正常に終わる経路の Goodbye! は確かめていない |
| `expected.exit_code` | 0 | `t/unit/test-repl-execution.lisp:12` it "repl-installed-terminal-controls-actual-runner-lifecycle" | render-prompt-cont が +repl-exit+ を返して REPL が終わると run-repl が 0 を返すことを :success の場合で確かめる (exit 組み込みで +repl-exit+ に至ることは `t/unit/test-repl-state.lisp:255` が確かめる)。セッションを exit で終えて 0 になる流れを最後まで駆動している |

### A08-ctrl-d-exits

`t/scenarios/A08/ctrl-d-exits.json` [削除 (先にテストを足す)]

シナリオの入口: 実 PTY の対話 REPL (キー入力 → 行エディタ → 送信 → 実行 → 端末への出力、exit/Ctrl-D で終了)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "there are active jobs" | `t/unit/test-repl.lisp:350` it "ctrl-d-warns-once-before-stopping-with-active-jobs" | %process-quit-output-event を直接 2 回呼ぶ (ジョブ監視は手で作り、REPL ループ・キー入力・PTY を通らない) | いいえ | 1 回目の quit イベントで "exit: there are active jobs. Exit again to leave." を出すことを確かめる。背景ジョブを打ってから Ctrl-D を押す経路は通らない |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:473` it "e2e-main-interactive-pty-initial-ctrl-d-exits-zero" | 実 PTY で nshell main を対話起動し Ctrl-D (code-char 4) を 1 回書く (%assert-interactive-pty-exit) | はい | ジョブのない状態で Ctrl-D 1 回の 0 終了を確かめる。背景ジョブがある状態で Ctrl-D を 2 回押した後の 0 終了は確かめていない |

### A08-exit-warns-about-job

`t/scenarios/A08/exit-warns-about-job.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "there are active jobs. Exit again to leave." | `t/unit/test-builtins-core.lisp:174` it "exit-warns-once-before-stopping-with-active-jobs" | ジョブがある状態で exit を呼び、出力が "exit: there are active jobs. Exit again to leave.\n" と一致することを確かめる |
| `expected.stream.contains[1]` | "A08_CONTINUED_8" | なし | unit は 1 回目の exit の後に running が真であることだけを見る。警告の後に別のコマンドを打ち、それが動くことを確かめるテストがない |
| `expected.exit_code` | 0 | なし | unit は 2 回の exit を続けて呼ぶ。間に別のコマンドを挟んでも 2 回目の exit で終わることを確かめるテストがない (挟んだコマンドで警告の状態が戻ると、シナリオは wait_exit で止まる) |
| `steps[6].contains` | "Exit again to leave." | `t/unit/test-builtins-core.lisp:174` it "exit-warns-once-before-stopping-with-active-jobs" | 1 回目の exit の出力に "Exit again to leave." を含むことを確かめる |

### A10-exec-replaces-shell

`t/scenarios/A10/exec-replaces-shell.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.equals` | "A10_EXEC_REPLACED\n" | なし | 最上位の exec の出力を見るテストは --json の入口 (`t/e2e/test-machine-json-golden.lisp:396`) で、envelope の stdout を見る。--command の exec で stdout がそのまま出ることを確かめるテストがない |
| `expected.stderr.equals` | "" | なし | --command の exec で stderr が空であることを確かめるテストがない |
| `expected.exit_code` | 0 | なし | --command の exec で終了コード 0 を確かめるテストがない |

### A12-no-config-skips-startup

`t/scenarios/A12/no-config-skips-startup.json` [golden へ移す]

```json
{
  "env": {},
  "expected": {
    "duration_ms": 0,
    "effects": [],
    "nshell_api": 1,
    "ok": true,
    "safety": {
      "level": "confirm",
      "reasons": [
        {
          "rule": "classify/argument-not-allowed",
          "text": "arguments outside the command's allowed form: A12_NO_CONFIG_OK\\n"
        }
      ]
    },
    "state": {
      "cwd": "$WORK",
      "env_changed": [],
      "jobs": []
    },
    "status": 0,
    "stderr": {
      "bytes": 0,
      "lines": 0,
      "text": "",
      "truncated": false
    },
    "stdout": {
      "bytes": 17,
      "lines": 1,
      "text": "A12_NO_CONFIG_OK\n",
      "truncated": false
    }
  },
  "files": {
    "config/nshell/init.lisp": "(echo A12_CONFIG_WAS_LOADED)\n"
  },
  "input": "printf \"A12_NO_CONFIG_OK\\n\""
}
```

この期待値は、aarch64-darwin でビルドした nshell に、golden の実行器と同じ作業ディレクトリ・環境・正規化で 3 回流し、`error.message` を除いた envelope 全体が 3 回とも一致したものです。Linux では流していません。

### A13-config-error-keeps-prompt

`t/scenarios/A13/config-error-keeps-prompt.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "init.lisp" | なし | unit は load-config-sources を (error "broken config") に差し替えて、メッセージに設定パスが入ることを見る。実ファイルの ')' を読んだときのメッセージに init.lisp のパスが出ることを確かめるテストがない |
| `expected.stream.contains[1]` | "A13_CONFIG_READY" | `t/integration/test-file-config.lisp:90` it "interactive-config-reports-loading-errors" | 読み込みのエラーを報告した後に %load-interactive-config が戻ること (REPL を止めない) を確かめる。その後のコマンド実行は e2e-main-interactive-pty-smoke (`t/e2e/test-smoke.lisp:439`) が確かめる |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY で exit を書き終了コード 0 を確かめる |
| `steps[2].contains` | "A13_CONFIG_READY" | `t/integration/test-file-config.lisp:90` it "interactive-config-reports-loading-errors" | シナリオ自身の印を待つ同期。設定エラーの後も起動が進むことは同じテストが確かめる |

### B01-B06-shell-caller-handoff

`t/scenarios/B01/shell-caller-handoff.json` [削除]

シナリオの入口: argv `-c TEXT` で nshell main を起動 (-c は /bin/sh に委譲)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stdout.equals` | "R04_CALLER_EDITOR\nR04_CALLER_SSH\nR04_CALLER_TRANSFER\nR04_CALLER_GIT\nR04_CALLER_MAKE\nR04_CALLER_AUTOMATION\n" | `t/e2e/test-smoke-script.lisp:55` it "e2e-main-shell-command-delegates-with-argv-and-login-config" | argv `-c TEXT` (-l なし。別ケースで -ilc) で main をサブプロセス起動 (%run-nshell-main) | はい | argv -c の printf スクリプトを main から /bin/sh に委譲し、stdout が sh の出力と完全一致することを確かめる。for ループは /bin/sh がそのまま実行する |
| `expected.stderr.equals` | "" | `t/e2e/test-smoke-script.lisp:55` it "e2e-main-shell-command-delegates-with-argv-and-login-config" | argv `-c TEXT` (-l なし。別ケースで -ilc) で main をサブプロセス起動 (%run-nshell-main) | はい | 同じテストで -c 委譲の stderr "" を確かめる |
| `expected.exit_code` | 0 | `t/e2e/test-smoke-script.lisp:55` it "e2e-main-shell-command-delegates-with-argv-and-login-config" | argv `-c TEXT` (-l なし。別ケースで -ilc) で main をサブプロセス起動 (%run-nshell-main) | はい | 同じテストの -c "" で終了コード 0 を確かめる |

### B02-approx-remote-shell-command-contract

`t/scenarios/B02/approx-remote-shell-command-contract.json` [golden へ移す]

```json
{
  "env": {},
  "expected": {
    "duration_ms": 0,
    "effects": [],
    "error": {
      "code": "E_COMMAND_FAILED",
      "message": "the command exited with status 23"
    },
    "nshell_api": 1,
    "ok": false,
    "safety": {
      "level": "confirm",
      "reasons": [
        {
          "rule": "classify/argument-not-allowed",
          "text": "arguments outside the command's allowed form: B02_REMOTE_COMMAND\\n"
        },
        {
          "rule": "classify/unknown-command",
          "text": "unknown command"
        }
      ]
    },
    "state": {
      "cwd": "$WORK",
      "env_changed": [],
      "jobs": []
    },
    "status": 23,
    "stderr": {
      "bytes": 0,
      "lines": 0,
      "text": "",
      "truncated": false
    },
    "stdout": {
      "bytes": 19,
      "lines": 1,
      "text": "B02_REMOTE_COMMAND\n",
      "truncated": false
    }
  },
  "files": {},
  "input": "printf \"B02_REMOTE_COMMAND\\n\"; exit 23"
}
```

この期待値は、aarch64-darwin でビルドした nshell に、golden の実行器と同じ作業ディレクトリ・環境・正規化で 3 回流し、`error.message` を除いた envelope 全体が 3 回とも一致したものです。Linux では流していません。

### B03-approx-remote-copy-output-is-clean

`t/scenarios/B03/approx-remote-copy-output-is-clean.json` [削除]

シナリオの入口: nshell --command TEXT (バッチ、command 種)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stdout.equals` | "B03_MACHINE_OUTPUT\n" | `t/e2e/test-smoke.lisp:427` it "e2e-main-adjacent-quoted-fragments-concatenate" | nshell --command TEXT を main サブプロセスで実行 (%run-nshell-main) | はい | --command で printf の書式の \n を解釈させ、stdout が "ab\n" と完全一致することを確かめる |
| `expected.stderr.equals` | "" | `t/e2e/test-smoke.lisp:427` it "e2e-main-adjacent-quoted-fragments-concatenate" | nshell --command TEXT を main サブプロセスで実行 (%run-nshell-main) | はい | 同じテストで stderr "" を確かめる |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:427` it "e2e-main-adjacent-quoted-fragments-concatenate" | nshell --command TEXT を main サブプロセスで実行 (%run-nshell-main) | はい | 同じテストで終了コード 0 を確かめる |

### B06-approx-shell-c-command-contract

`t/scenarios/B06/approx-shell-c-command-contract.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.equals` | "B06_SHELL_C\n" | `t/e2e/test-smoke-script.lisp:55` it "e2e-main-shell-command-delegates-with-argv-and-login-config" | -c の printf の stdout が完全一致することを確かめる |
| `expected.stderr.equals` | "B06_STDERR\n" | なし | e2e は -c の stderr が "" であることしか見ず、/bin/sh が stderr に書いた内容が届くことを確かめるテストがない |
| `expected.exit_code` | 0 | `t/e2e/test-smoke-script.lisp:55` it "e2e-main-shell-command-delegates-with-argv-and-login-config" | -c 委譲の終了コード 0 を確かめる |

### B07-B08-interactive-callers

`t/scenarios/B07/interactive-callers.json` [削除 (先にテストを足す)]

シナリオの入口: 実 PTY の対話 REPL を引数 -i 付きで起動 (キー入力 → 行エディタ → 送信 → 実行 → 端末への出力)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "R04_INTERACTIVE_CALLER_OK" | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY で nshell main を対話起動 (--no-config --no-history、-i なし) | いいえ | 実 PTY の対話 REPL に打った printf の出力が端末に届くことは %e2e-pty-await-ready (`t/e2e/test-smoke.lisp:243`) が確かめるが、-i を付けた起動と環境変数の展開は通らない。前の回の判定で引用した T06 は .lisp のテストではない |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY で nshell main を対話起動 (--no-config --no-history、-i なし) | いいえ | exit を書き終了コード 0 を確かめる。-i 付きの起動ではない |
| `steps[2].contains` | "R04_INTERACTIVE_CALLER_OK" | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY で nshell main を対話起動 (--no-config --no-history、-i なし) | いいえ | シナリオ自身の印を待つ同期。-i なしの起動で printf の出力を待つ |

### B09-batch-command-uses-nshell-builtins

`t/scenarios/B09/batch-command-uses-nshell-builtins.json` [削除 (先にテストを足す)]

シナリオの入口: nshell --command TEXT (バッチ、command 種)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stdout.equals` | "R04_NSHELL_BUILTIN_GUARD\n" | `t/unit/test-builtins-core-string.lisp:4` it "string-builtin-covers-core-fish-style-subcommands" | string ビルトインの関数を直接呼ぶ (main も --command も通らない) | いいえ | string upper の結果が "HELLO\n" と一致することを確かめる。--command で string upper を実行するテストはない |
| `expected.stderr.equals` | "" | `t/e2e/test-smoke.lisp:402` it "e2e-main-status-variable-follows-last-command" | nshell --command TEXT を main サブプロセスで実行 (%run-nshell-main) | はい | --command のビルトイン (false, printf) の実行で stderr "" を確かめる。string upper ではない |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:402` it "e2e-main-status-variable-follows-last-command" | nshell --command TEXT を main サブプロセスで実行 (%run-nshell-main) | はい | --command のビルトイン実行で終了コード 0 を確かめる。string upper ではない |

### B09-command-stdio-and-status

`t/scenarios/B09/command-stdio-and-status.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.equals` | "B09_STDOUT\n" | `t/e2e/test-smoke-script.lisp:55` it "e2e-main-shell-command-delegates-with-argv-and-login-config" | -c の printf の stdout が完全一致することを確かめる |
| `expected.stderr.equals` | "B09_STDERR\n" | なし | e2e は -c の stderr が "" であることしか見ず、stderr の中身が届くことを確かめるテストがない |
| `expected.exit_code` | 23 | `t/e2e/test-smoke-script.lisp:55` it "e2e-main-shell-command-delegates-with-argv-and-login-config" | -c の exit 37 で終了コード 37 がそのまま返ることを確かめる (23 と同じ類) |

### B09-empty-shell-command

`t/scenarios/B09/empty-shell-command.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.equals` | "" | なし | e2e の -c "" は追加の引数を渡さない。-c "" r04-zero -- -leading のように - で始まる引数が後に続く入力を確かめるテストがない |
| `expected.stderr.equals` | "" | なし | 同じ理由で、この引数列で stderr が空 (使い方のエラーにならない) ことを確かめるテストがない |
| `expected.exit_code` | 0 | なし | 同じ理由で、この引数列で終了コード 0 を確かめるテストがない |

### B09-pty-command-uses-nshell-builtins

`t/scenarios/B09/pty-command-uses-nshell-builtins.json` [残す]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.equals` | "R04_NSHELL_PTY_BUILTIN_GUARD\r\n" | なし | 端末上の --command で端末設定が変わらないことは `t/e2e/test-smoke.lisp:335` が見るが、出力の中身は見ない。端末に "R04_NSHELL_PTY_BUILTIN_GUARD\r\n" だけが出て制御列などが混ざらないことを確かめるテストがない |
| `expected.exit_code` | 0 | なし | tty 上のバッチ実行の終了コードを確かめるテストは、--command true の端末設定比較 (:335) だけで、終了コードは %assert-pty-child-exit の 0 を見る。stream と合わせた確認ではない |

### B09-shell-command-argv

`t/scenarios/B09/shell-command-argv.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.equals` | "r04-zero\nspace arg\nsingle' quote\nline one\nline two\n--\n-leading\nR04_STDIN_OK\n" | なし | e2e は $0〜$3 (空文字列、空白、--) と -c cat への stdin を確かめるが、単引用符、改行を含む引数、-- の後の -leading、$4・$5 と read ループを確かめるテストがない |
| `expected.stderr.equals` | "" | `t/e2e/test-smoke-script.lisp:55` it "e2e-main-shell-command-delegates-with-argv-and-login-config" | -c 委譲の stderr が "" であることを確かめる |
| `expected.exit_code` | 0 | なし | この引数列 (-- の後に -leading) を受け付けて 0 終了することを確かめるテストがない |

### B10-login-command-environment

`t/scenarios/B10/login-command-environment.json` [残す]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.equals` | "B10_PATH_OK\r\n" | なし | e2e は --config で渡した設定の export が -ilc env に届き、設定の echo が stdout に出ないことを確かめる。既定の設定パス ($HOME/.config/nshell/init.lisp) から読むこと、export した PATH で /bin/sh がコマンドを探すこと、tty 上で端末に "B10_PATH_OK\r\n" だけが出ることを確かめるテストがない |
| `expected.exit_code` | 0 | `t/e2e/test-smoke-script.lisp:55` it "e2e-main-shell-command-delegates-with-argv-and-login-config" | -ilc env の終了コード 0 を確かめる |

### C01-batch-command

`t/scenarios/C01/batch-command.json` [削除 (先にテストを足す)]

シナリオの入口: nshell --command TEXT (バッチ、command 種)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stdout.contains[0]` | "SCENARIO_BATCH_COMMAND_OK" | `t/e2e/test-smoke-script.lisp:98` it "e2e-main-command-exposes-trailing-argv" | nshell --command TEXT を main サブプロセスで実行 (%run-nshell-main) | はい | --command の "echo ...; echo ..." でビルトイン echo の出力が stdout に出ることを確かめる |
| `expected.stdout.excludes[0]` | "SCENARIO_BATCH_OK" | `t/unit/test-builtins-source-pipeline.lisp:33` it "source-pipeline-redirects-builtin-output" | source ビルトインの経路 (call-source-file) を直接呼ぶ (main も --command も通らない) | いいえ | source で読んだ "echo redirected > ファイル" の出力が "" であることを確かめる。--command ではない |
| `expected.stderr.equals` | "" | `t/e2e/test-smoke-script.lisp:98` it "e2e-main-command-exposes-trailing-argv" | nshell --command TEXT を main サブプロセスで実行 (%run-nshell-main) | はい | %assert-nshell-main-result が --command の stderr "" を確かめる |
| `expected.exit_code` | 0 | `t/e2e/test-smoke-script.lisp:98` it "e2e-main-command-exposes-trailing-argv" | nshell --command TEXT を main サブプロセスで実行 (%run-nshell-main) | はい | --command の終了コード 0 を確かめる |
| `expected.side_effects.files[0].path` | "result.txt" | `t/unit/test-builtins-source-pipeline.lisp:33` it "source-pipeline-redirects-builtin-output" | source ビルトインの経路 (call-source-file) を直接呼ぶ (main も --command も通らない) | いいえ | リダイレクト先のファイルを読む。--command ではない |
| `expected.side_effects.files[0].exists` | true | `t/unit/test-builtins-source-pipeline.lisp:33` it "source-pipeline-redirects-builtin-output" | source ビルトインの経路 (call-source-file) を直接呼ぶ (main も --command も通らない) | いいえ | read-test-file-line でファイルを読めること (存在) を確かめる。--command ではない |
| `expected.side_effects.files[0].contains[0]` | "SCENARIO_BATCH_OK" | `t/unit/test-builtins-source-pipeline.lisp:33` it "source-pipeline-redirects-builtin-output" | source ビルトインの経路 (call-source-file) を直接呼ぶ (main も --command も通らない) | いいえ | ファイルの中身が "redirected" であることを確かめる。--command ではない |

### C01-batch-script

`t/scenarios/C01/batch-script.json` [削除]

シナリオの入口: nshell FILE.nsh のスクリプトモード (バッチ、script 種)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stdout.contains[0]` | "SCENARIO_SCRIPT_OK" | `t/e2e/test-smoke-script.lisp:30` it "e2e-main-script-preserves-flag-like-argv" | スクリプトファイルを argv に渡して main サブプロセスで実行 (%assert-nshell-main-result) | はい | スクリプトファイルの bare の "echo arg=$argv[1]" を実行し、stdout にその出力が出ることを確かめる |
| `expected.stderr.equals` | "" | `t/e2e/test-smoke-script.lisp:30` it "e2e-main-script-preserves-flag-like-argv" | スクリプトファイルを argv に渡して main サブプロセスで実行 (%assert-nshell-main-result) | はい | %assert-nshell-main-result がスクリプト実行の stderr "" を確かめる |
| `expected.exit_code` | 0 | `t/e2e/test-smoke-script.lisp:30` it "e2e-main-script-preserves-flag-like-argv" | スクリプトファイルを argv に渡して main サブプロセスで実行 (%assert-nshell-main-result) | はい | スクリプト実行の終了コード 0 を確かめる |

### C01-batch-stdin

`t/scenarios/C01/batch-stdin.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.contains[0]` | "SCENARIO_STDIN_OK" | なし | stdin を読む e2e (`t/e2e/test-smoke-script.lisp:302`) は S 式 (if t (echo stdin-ok)) だけを流す。bare の echo を stdin から実行することを確かめるテストがない |
| `expected.stderr.equals` | "" | なし | 同じ理由で、bare の行を stdin から実行したときに stderr が空であることを確かめるテストがない |
| `expected.exit_code` | 0 | なし | 同じ理由で、bare の行を stdin から実行したときの終了コード 0 を確かめるテストがない (unit の `t/unit/test-repl.lisp:547` は true を流し 0 を見るが、出力は見ない) |

### C01-pty-paste

`t/scenarios/C01/pty-paste.json` [削除 (先にテストを足す)]

シナリオの入口: 実 PTY の対話 REPL (キー入力 → 行エディタ → 送信 → 実行 → 端末への出力、exit/Ctrl-D で終了)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "SCENARIO_PTY_PASTE_OK" | `t/e2e/test-smoke-input.lisp:130` it "e2e-bracketed-paste-normalizes-newlines-and-undos-once" | キー列を文字列から作り reducer (apply-key-events-to-input-state) に直接かける (PTY も REPL ループも実行も通らない) | いいえ | bracketed paste のバイト列が入力バッファになることだけを確かめる。貼り付けた行を実行して端末に出力が出ることは通らない。前の回の判定で引用した F08 は .lisp のテストではない |
| `expected.screen.contains[0]` | "SCENARIO_PTY_PASTE_OK" | なし | なし (.lisp のテストに端末の画面を再現するものはない) | いいえ | 出力が終了後の画面に残ることは端末エミュレータで画面を組み立てないと確かめられない。前の回の判定で引用した F01 は .lisp のテストではない |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY で nshell main を対話起動 (--no-config --no-history、-i なし) | はい | 実 PTY で exit を書き終了コード 0 を確かめる |
| `steps[2].contains` | "SCENARIO_PTY_PASTE_OK" | `t/e2e/test-smoke-input.lisp:130` it "e2e-bracketed-paste-normalizes-newlines-and-undos-once" | キー列を文字列から作り reducer (apply-key-events-to-input-state) に直接かける (PTY も REPL ループも実行も通らない) | いいえ | シナリオ自身の印を待つ同期。reducer のテストは実行の出力を待たない |

### C02-quoted-unicode-arguments

`t/scenarios/C02/quoted-unicode-arguments.json` [golden へ移す]

```json
{
  "env": {},
  "expected": {
    "duration_ms": 0,
    "effects": [],
    "nshell_api": 1,
    "ok": true,
    "safety": {
      "level": "confirm",
      "reasons": [
        {
          "rule": "classify/argument-not-allowed",
          "text": "arguments outside the command's allowed form: <%s>\\n"
        }
      ]
    },
    "state": {
      "cwd": "$WORK",
      "env_changed": [],
      "jobs": []
    },
    "status": 0,
    "stderr": {
      "bytes": 0,
      "lines": 0,
      "text": "",
      "truncated": false
    },
    "stdout": {
      "bytes": 31,
      "lines": 3,
      "text": "<a b>\n<雪だるま>\n<quote:\">\n",
      "truncated": false
    }
  },
  "files": {},
  "input": "printf \"<%s>\\n\" \"a b\" \"雪だるま\" \"quote:\\\"\""
}
```

この期待値は、aarch64-darwin でビルドした nshell に、golden の実行器と同じ作業ディレクトリ・環境・正規化で 3 回流し、`error.message` を除いた envelope 全体が 3 回とも一致したものです。Linux では流していません。

### C03-path-search-and-absolute-path

`t/scenarios/C03/path-search-and-absolute-path.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.contains[0]` | "C03_PATH_FOUND" | なし | PATH から外部コマンドを探すテストは絶対パスの要素 ($WORK/bin、golden の proposal-02) だけで、相対の要素 bin から探すことを確かめるテストがない |
| `expected.stdout.contains[1]` | "C03_ABSOLUTE" | `t/e2e/test-smoke-script.lisp:161` it "e2e-main-command-expands-process-substitution" | --command で絶対パスの外部コマンド (%resolve-real-external-executable の printf) を実行し、その出力 process-ok が stdout に出ることを確かめる |
| `expected.exit_code` | 0 | なし | 相対の PATH 要素を含む実行を最後まで進めて 0 終了することを確かめるテストがない |

### C04-missing-command-suggestion-and-status

`t/scenarios/C04/missing-command-suggestion-and-status.json` [削除 (先にテストを足す)]

シナリオの入口: nshell --command TEXT (バッチ、command 種)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stdout.equals` | "" | `t/unit/test-command-failure.lisp:271` it "batch diagnostics suggest known commands on stderr and preserve status 127 without spawning" | %run-batch-source-lines を直接呼ぶ (main も --command の引数解析も通らない。spawn は差し替え) | いいえ | "gti" を渡し stdout "" を確かめる |
| `expected.stderr.contains[0]` | "command not found" | `t/unit/test-command-failure.lisp:271` it "batch diagnostics suggest known commands on stderr and preserve status 127 without spawning" | %run-batch-source-lines を直接呼ぶ (main も --command の引数解析も通らない。spawn は差し替え) | いいえ | stderr に "nshell: gti: command not found" が 1 度だけ出ることを確かめる |
| `expected.stderr.contains[1]` | "echo" | `t/unit/test-highlight.lisp:480` it "command-corrections-propose-builtins-one-edit-away" | %repl-command-corrections 相当の候補関数を直接呼ぶ | いいえ | "ehco" の候補にビルトイン "echo" を含むことを確かめる。"echp" ではなく、stderr への出力も通らない |
| `expected.exit_code` | 127 | `t/unit/test-command-failure.lisp:271` it "batch diagnostics suggest known commands on stderr and preserve status 127 without spawning" | %run-batch-source-lines を直接呼ぶ (main も --command の引数解析も通らない。spawn は差し替え) | いいえ | 終了コードと *last-exit-code* が 127 であることを確かめる |

### C05-last-exit-status-is-visible

`t/scenarios/C05/last-exit-status-is-visible.json` [削除 (先にテストを足す)]

シナリオの入口: nshell --command TEXT (バッチ、command 種)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stdout.contains[0]` | "C05_STATUS:1" | `t/e2e/test-smoke-script.lisp:366` it "e2e-main-eval-updates-last-exit-status" | nshell --command TEXT を main サブプロセスで実行 (%run-nshell-main) | はい | --command の "eval 'false'; echo eval-status=$?" で $? が 1 になることを確かめる。eval を挟まない "false; ... $?" と、引用した "$?" を printf に渡す形は通らない (`t/e2e/test-smoke.lisp:402` は $status) |
| `expected.exit_code` | 0 | `t/e2e/test-smoke-script.lisp:366` it "e2e-main-eval-updates-last-exit-status" | nshell --command TEXT を main サブプロセスで実行 (%run-nshell-main) | はい | 同じテストで終了コード 0 を確かめる |

### C06-builtin-reads-stdin

`t/scenarios/C06/builtin-reads-stdin.json` [golden へ移す]

```json
{
  "env": {},
  "expected": {
    "duration_ms": 0,
    "effects": [],
    "nshell_api": 1,
    "ok": true,
    "safety": {
      "level": "confirm",
      "reasons": [
        {
          "rule": "classify/argument-not-allowed",
          "text": "arguments outside the command's allowed form: abc\\n"
        },
        {
          "rule": "classify/unknown-command",
          "text": "unknown command"
        }
      ]
    },
    "state": {
      "cwd": "$WORK",
      "env_changed": [],
      "jobs": []
    },
    "status": 0,
    "stderr": {
      "bytes": 0,
      "lines": 0,
      "text": "",
      "truncated": false
    },
    "stdout": {
      "bytes": 4,
      "lines": 1,
      "text": "ABC\n",
      "truncated": false
    }
  },
  "files": {},
  "input": "printf \"abc\\n\" | string upper"
}
```

この期待値は、aarch64-darwin でビルドした nshell に、golden の実行器と同じ作業ディレクトリ・環境・正規化で 3 回流し、`error.message` を除いた envelope 全体が 3 回とも一致したものです。Linux では流していません。

### C06-pipeline-streams-all-stages

`t/scenarios/C06/pipeline-streams-all-stages.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.equals` | "C06_PIPELINE\n" | なし | bare-line のパイプラインの出力を完全一致で見るテストは \|& の 2 段 (`t/e2e/test-smoke-script.lisp:147`、search で含むかだけ) で、ビルトインから外部 2 段に流す 3 段の出力が stdout に完全一致で出ることを確かめるテストがない |
| `expected.stderr.equals` | "" | `t/e2e/test-smoke-script.lisp:147` it "e2e-main-command-merges-stderr-with-pipe-and-ampersand" | %assert-nshell-main-result が bare-line の外部パイプラインで stderr が "" であることを確かめる |
| `expected.exit_code` | 0 | `t/e2e/test-smoke-script.lisp:147` it "e2e-main-command-merges-stderr-with-pipe-and-ampersand" | bare-line の外部パイプラインの終了コード 0 を確かめる |

### C06-pipeline-streams-mixed-stages

`t/scenarios/C06/pipeline-streams-mixed-stages.json` [削除]

シナリオの入口: nshell FILE.nsh のスクリプトモード (バッチ、script 種)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stdout.equals` | "C06_MIXED_STREAM\n" | `t/spec/probes.lisp:217` it "language-probe pipe-sexp v0.7.0 baseline" | NSHELL_BIN のバイナリに case.nsh を渡すスクリプトモード (`t/spec/support.lisp:281` %run-probe) | はい | スクリプトモードで (\| (echo hi) (tr a-z A-Z)) を実行し、stdout が "HI\n" と一致することを確かめる (`docs/design/conformance/language-probes-v0.7.0.json` の pipe-sexp)。ビルトインから外部へ流す S 式パイプラインで、シナリオと同じ種類 |
| `expected.stderr.equals` | "" | `t/spec/probes.lisp:217` it "language-probe pipe-sexp v0.7.0 baseline" | NSHELL_BIN のバイナリに case.nsh を渡すスクリプトモード (`t/spec/support.lisp:281` %run-probe) | はい | 同じ probe で stderr "" を確かめる |
| `expected.exit_code` | 0 | `t/spec/probes.lisp:217` it "language-probe pipe-sexp v0.7.0 baseline" | NSHELL_BIN のバイナリに case.nsh を渡すスクリプトモード (`t/spec/support.lisp:281` %run-probe) | はい | 同じ probe で終了コード 0 を確かめる |

### C07-redirection-family

`t/scenarios/C07/redirection-family.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.contains[0]` | "C07_OVERWRITE" | `t/unit/test-builtins-source-pipeline.lisp:33` it "source-pipeline-redirects-builtin-output" | bare-line のビルトインの > がファイルに書くことを確かめる。そのファイルを cat < で読むことは `t/e2e/test-smoke-pipeline.lisp:12` (cat < input \| cat > output) が確かめる |
| `expected.stdout.contains[1]` | "C07_APPEND" | なし | bare-line のビルトインの >> で追記することを実行で確かめるテストがない (probe redir-append は S 式、unit :4 は開くモードだけ) |
| `expected.stdout.contains[2]` | "C07_PIPE_ERR" | `t/e2e/test-smoke-script.lisp:147` it "e2e-main-command-merges-stderr-with-pipe-and-ampersand" | bare-line の "sh -c '... >&2' \|& cat" で stderr が下流に流れ stdout に出ることを確かめる |
| `expected.stderr.equals` | "C07_MERGED\n" | なし | ビルトインの >&2 2>&1 の順で出力が stderr に残ることを確かめるテストがない (:257 の順序テストは S 式と外部コマンドで 1>& 2 > file) |
| `expected.exit_code` | 0 | なし | このリダイレクトの並びを最後まで実行して 0 終了することを確かめるテストがない |
| `expected.side_effects.files[0].path` | "redirected.txt" | `t/unit/test-builtins-source-pipeline.lisp:33` it "source-pipeline-redirects-builtin-output" | リダイレクト先のファイルを読む。ファイルの指定は file の contains と一組 |
| `expected.side_effects.files[0].contains[0]` | "C07_OVERWRITE" | `t/unit/test-builtins-source-pipeline.lisp:33` it "source-pipeline-redirects-builtin-output" | bare-line のビルトインの > でファイルの中身が書いた文字列になることを確かめる |
| `expected.side_effects.files[0].contains[1]` | "C07_APPEND" | なし | ビルトインの >> でファイルに追記した中身を確かめるテストがない |
| `expected.side_effects.files[1].path` | "dup.txt" | なし | ビルトインの 3>dup.txt 1>&3 を確かめるテストがない (:270 は S 式と外部コマンド、:282 は 3>& 1 だけ) |
| `expected.side_effects.files[1].contains[0]` | "C07_DUP" | なし | 同上、dup.txt の中身を確かめるテストがない |
| `expected.side_effects.files[2].path` | "force.txt" | なし | >\| で書くことは unit (`t/unit/test-execute-reader-redirect.lisp:4`) が開くモードだけを見る。bare-line のビルトインで実行するテストがない |
| `expected.side_effects.files[2].contains[0]` | "C07_FORCE" | なし | 同上、force.txt の中身を確かめるテストがない |
| `expected.side_effects.files[3].path` | "both.txt" | なし | &> は e2e (:236) が S 式と外部コマンドで見る。bare-line のビルトインで確かめるテストがない |
| `expected.side_effects.files[3].contains[0]` | "C07_BOTH" | なし | 同上、both.txt の中身を確かめるテストがない |
| `expected.side_effects.files[4].path` | "err.txt" | なし | ビルトインの 2> を実行するテストがない (probe redir-stderr は S 式と外部 ls) |
| `expected.side_effects.files[4].exists` | true | なし | 同上、err.txt ができることを確かめるテストがない |

### C08-here-doc-and-here-string

`t/scenarios/C08/here-doc-and-here-string.json` [削除 (先にテストを足す)]

シナリオの入口: nshell FILE.nsh のスクリプトモード (バッチ、script 種)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stdout.contains[0]` | "C08_HEREDOC" | `t/e2e/test-smoke-script.lisp:328` it "e2e-main-here-document-quoted-delimiter-keeps-body-literal" | nshell --command TEXT を main サブプロセスで実行 (%run-nshell-main) | いいえ | --command で引用した区切りのヒアドキュメントを外部 cat に渡し、本文がそのまま stdout に出ることを確かめる。スクリプトモードではない。スクリプトモードの bare-heredoc probe は L7 の行 (`t/spec/l7-rows.lisp:896`) で v0.8 の E_UNSUPPORTED_SYNTAX を期待する it-fails で、v0.7.0 baseline のテストはない |
| `expected.stdout.contains[1]` | "C08_HERESTRING" | `t/spec/probes.lisp:217` it "language-probe bare-herestring v0.7.0 baseline" | NSHELL_BIN のバイナリに case.nsh を渡すスクリプトモード (`t/spec/support.lisp:281` %run-probe) | はい | スクリプトモードで bare の cat <<< here を実行し、stdout が "here\n" と一致することを確かめる |
| `expected.exit_code` | 0 | `t/spec/probes.lisp:217` it "language-probe bare-herestring v0.7.0 baseline" | NSHELL_BIN のバイナリに case.nsh を渡すスクリプトモード (`t/spec/support.lisp:281` %run-probe) | はい | 同じ probe で終了コード 0 を確かめる。ヒアドキュメントを含むスクリプト全体の終了コードではない |

### C09-background-command-returns

`t/scenarios/C09/background-command-returns.json` [削除 (先にテストを足す)]

シナリオの入口: nshell FILE.nsh のスクリプトモード (バッチ、script 種)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stdout.contains[0]` | "C09_BACKGROUND_DONE" | `t/spec/probes.lisp:217` it "language-probe bare-background v0.7.0 baseline" | NSHELL_BIN のバイナリに case.nsh を渡すスクリプトモード (`t/spec/support.lisp:281` %run-probe) | はい | スクリプトモードで改行区切りの sleep 0 &、wait、echo bg-ok を実行し stdout "bg-ok\n" を確かめる。1 行の "sleep 0.1 &; wait; ..." はスクリプトモードで通らず、その読み方は scanner の unit (`t/unit/test-sexp-scanner.lisp:15`、scan-input を直接呼ぶ) だけが確かめる |
| `expected.exit_code` | 0 | `t/spec/probes.lisp:217` it "language-probe bare-background v0.7.0 baseline" | NSHELL_BIN のバイナリに case.nsh を渡すスクリプトモード (`t/spec/support.lisp:281` %run-probe) | はい | 同じ probe で終了コード 0 を確かめる (改行区切りの入力) |

### C10-short-circuit-followed-by-sequence

`t/scenarios/C10/short-circuit-followed-by-sequence.json` [削除 (先にテストを足す)]

シナリオの入口: nshell FILE.nsh のスクリプトモード (バッチ、script 種)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stdout.contains[0]` | "next" | `t/unit/test-sexp-evaluator.lisp:1114` it "applies-command-failure-policy-at-sequence-item-boundaries" | evaluate-reader-result-in-context を直接呼び、ビルトインを差し替える (main もスクリプトモードも通らない) | いいえ | "false && echo skipped; echo continued" を評価し、実行されたのが false と echo continued だけであることを確かめる。出力は差し替えたビルトインで出ない |
| `expected.exit_code` | 0 | `t/unit/test-sexp-evaluator.lisp:1114` it "applies-command-failure-policy-at-sequence-item-boundaries" | evaluate-reader-result-in-context を直接呼び、ビルトインを差し替える (main もスクリプトモードも通らない) | いいえ | 同じ評価の状態が 0 であることを確かめる。プロセスの終了コードではない |

### C11-temporary-command-environment

`t/scenarios/C11/temporary-command-environment.json` [削除 (先にテストを足す)]

シナリオの入口: nshell --command TEXT (バッチ、command 種)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stdout.contains[0]` | "C11_VALUE=inside" | `t/spec/probes.lisp:217` it "language-probe bare-assign v0.7.0 baseline" | NSHELL_BIN のバイナリに case.nsh を渡すスクリプトモード (`t/spec/support.lisp:281` %run-probe) | いいえ | スクリプトモードで FOO=bar sh -c "echo foo=$FOO" を実行し、一時代入が子に届くことを確かめる。--command ではない |
| `expected.stdout.contains[1]` | "C11_AFTER:" | `t/unit/test-execute-pipeline.lisp:1610` it "prefix-assignment-exports-only-for-that-command" | execute-command-node-in-context を直接呼び、実行を差し替える (main も --command も通らない) | いいえ | FOO=bar echo x の後に FOO がセッションで未定義であることを確かめる。stdout は確かめない |
| `expected.stdout.excludes[0]` | "C11_AFTER:inside" | `t/unit/test-execute-pipeline.lisp:1610` it "prefix-assignment-exports-only-for-that-command" | execute-command-node-in-context を直接呼び、実行を差し替える (main も --command も通らない) | いいえ | 実行後に env-defined-p が偽であることを確かめる。stdout は確かめない |
| `expected.exit_code` | 0 | `t/spec/probes.lisp:217` it "language-probe bare-assign v0.7.0 baseline" | NSHELL_BIN のバイナリに case.nsh を渡すスクリプトモード (`t/spec/support.lisp:281` %run-probe) | いいえ | 同じ probe で終了コード 0 を確かめる。--command ではない |

### C12-approx-privileged-command-dispatch

`t/scenarios/C12/approx-privileged-command-dispatch.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "C12_SUDO_WRAPPER" | なし | PATH 上の sudo のような包むコマンドが自分の出力を出してから引数のコマンドを exec する流れを確かめるテストがない。PATH も相対の要素 bin を使い、C03 と同じく確かめていない |
| `expected.stream.contains[1]` | "C12_DOAS_WRAPPER" | なし | 同上 (doas) |
| `expected.stream.contains[2]` | "C12_SUDO_OK" | なし | 包むコマンドに渡した echo $C12_SUDO_OUTPUT の展開と実行の結果を確かめるテストがない |
| `expected.stream.contains[3]` | "C12_DOAS_OK" | なし | 同上 (doas) |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY で exit を書き終了コード 0 を確かめる |
| `steps[2].contains` | "C12_12" | `t/e2e/test-smoke-script.lisp:176` it "e2e-main-command-expands-documented-core-forms" | シナリオ自身の印 C12_$((6*2)) を待つ同期。--command の算術展開 $((1 + 2 * 3)) が arith=7 になることを確かめる |

### C13-glob-patterns-and-unmatched-path

`t/scenarios/C13/glob-patterns-and-unmatched-path.json` [golden へ移す]

```json
{
  "env": {},
  "expected": {
    "duration_ms": 0,
    "effects": [],
    "nshell_api": 1,
    "ok": true,
    "safety": {
      "level": "confirm",
      "reasons": [
        {
          "rule": "classify/argument-not-allowed",
          "text": "arguments outside the command's allowed form: %s\\n"
        }
      ]
    },
    "state": {
      "cwd": "$WORK",
      "env_changed": [],
      "jobs": []
    },
    "status": 0,
    "stderr": {
      "bytes": 0,
      "lines": 0,
      "text": "",
      "truncated": false
    },
    "stdout": {
      "bytes": 108,
      "lines": 10,
      "text": "file1.txt\nfile2.txt\nplain.txt\nfile1.txt\nfile2.txt\nfile1.txt\nfile2.txt\nplain.txt\nsub/deep.txt\nno-match-*.zzz\n",
      "truncated": false
    }
  },
  "files": {
    ".hidden.txt": "hidden\n",
    "file1.txt": "one\n",
    "file2.txt": "two\n",
    "plain.txt": "plain\n",
    "sub/deep.txt": "deep\n"
  },
  "input": "printf '%s\\n' *.txt file?.txt **/*.txt no-match-*.zzz"
}
```

この期待値は、aarch64-darwin でビルドした nshell に、golden の実行器と同じ作業ディレクトリ・環境・正規化で 3 回流し、`error.message` を除いた envelope 全体が 3 回とも一致したものです。Linux では流していません。

### C14-tilde-and-brace-expansion

`t/scenarios/C14/tilde-and-brace-expansion.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.contains[0]` | "C14_HOME_VALUE" | なし | チルダは spec の tilde probe が S 式 (echo ~ ~/x) で、unit が expand-tilde を直接呼んで確かめる。bare-line の外部コマンドの引数 ~/home-marker.txt を HOME に展開して実行することを確かめるテストがない |
| `expected.stdout.contains[1]` | "item-one" | `t/e2e/test-smoke-script.lisp:176` it "e2e-main-command-expands-documented-core-forms" | --command の bare-line で echo brace=a{b,c} が "brace=ab brace=ac" になることを確かめる |
| `expected.stdout.contains[2]` | "item-two" | `t/e2e/test-smoke-script.lisp:176` it "e2e-main-command-expands-documented-core-forms" | 同じテストで brace の 2 語目が出ることを確かめる |
| `expected.exit_code` | 0 | `t/e2e/test-smoke-script.lisp:176` it "e2e-main-command-expands-documented-core-forms" | 同じテストで終了コード 0 を確かめる |

### C15-approx-captured-command-value

`t/scenarios/C15/approx-captured-command-value.json` [golden へ移す]

```json
{
  "env": {},
  "expected": {
    "duration_ms": 0,
    "effects": [],
    "nshell_api": 1,
    "ok": true,
    "safety": {
      "level": "confirm",
      "reasons": [
        {
          "rule": "classify/environment-assignment",
          "text": "assigning this environment variable can change what the command runs"
        },
        {
          "rule": "classify/argument-not-allowed",
          "text": "arguments outside the command's allowed form: %s\\n"
        }
      ]
    },
    "state": {
      "cwd": "$WORK",
      "env_changed": [],
      "jobs": []
    },
    "status": 0,
    "stderr": {
      "bytes": 0,
      "lines": 0,
      "text": "",
      "truncated": false
    },
    "stdout": {
      "bytes": 10,
      "lines": 1,
      "text": "C15_VALUE\n",
      "truncated": false
    }
  },
  "files": {},
  "input": "value=$(printf C15_VALUE); printf \"%s\\n\" \"$value\""
}
```

この期待値は、aarch64-darwin でビルドした nshell に、golden の実行器と同じ作業ディレクトリ・環境・正規化で 3 回流し、`error.message` を除いた envelope 全体が 3 回とも一致したものです。Linux では流していません。

### C16-approx-process-substitution-input

`t/scenarios/C16/approx-process-substitution-input.json` [削除]

シナリオの入口: nshell FILE.nsh のスクリプトモード (バッチ、script 種)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stdout.equals` | "C16_PROCESS_VALUE" | `t/spec/probes.lisp:217` it "language-probe procsub-bare v0.7.0 baseline" | NSHELL_BIN のバイナリに case.nsh を渡すスクリプトモード (`t/spec/support.lisp:281` %run-probe) | はい | スクリプトモードで bare の cat <(echo psb) を実行し、stdout が "psb\n" と行と末尾改行の形まで一致することを確かめる (同じ種類の値) |
| `expected.exit_code` | 0 | `t/spec/probes.lisp:217` it "language-probe procsub-bare v0.7.0 baseline" | NSHELL_BIN のバイナリに case.nsh を渡すスクリプトモード (`t/spec/support.lisp:281` %run-probe) | はい | 同じ probe で終了コード 0 を確かめる |

### C17-approx-large-binary-and-invalid-utf8-output

`t/scenarios/C17/approx-large-binary-and-invalid-utf8-output.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.contains[0]` | "C17_LARGE" | なし | nshell --command で外部パイプライン yes \| head -n 10000 の大きな出力をそのまま通すことを確かめるテストはない |
| `expected.stdout.contains[1]` | "C17_BINARY" | なし | printf 組み込みの \000 と \377 を確かめるのは `t/unit/test-builtins-core.lisp:90` だけで、文字列で比べており、stdout に出るバイト列は確かめていない |
| `expected.exit_code` | 0 | なし | この --command 全体 (外部パイプラインのあとに printf) が 0 で終わることを確かめるテストはない。`t/e2e/test-smoke-script.lisp` の --command 系は別の入力 |

### C18-approx-sigpipe-is-quiet

`t/scenarios/C18/approx-sigpipe-is-quiet.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "y\r\n" | なし | integration (`t/integration/test-process.lisp:1359`) は上流が 0 以外で終わることだけを見る。外部から外部への yes \| head -1 で下流の出力 "y" が出ることを確かめるテストがない |
| `expected.stream.excludes[0]` | "Broken pipe" | なし | 外部の上流が SIGPIPE で止まったときに "Broken pipe" などのメッセージが出ないこと (stderr が空) を確かめるテストがない。unit の EPIPE はビルトインの上流 |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY で exit を書き終了コード 0 を確かめる |
| `steps[2].contains` | "y\r\n" | なし | 同期の印 "y" はこのコマンドの出力で、出力を確かめるテストがない |

### D01-approx-editor-tty

`t/scenarios/D01/approx-editor-tty.json` [削除]

シナリオの入口: 実 PTY の対話 REPL (キー入力 → 行エディタ → 送信 → 実行 → 端末への出力、exit/Ctrl-D で終了)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "D01_EDITOR_READY" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY で nshell main を対話起動し、行を PTY に書いて出力を読む (%call-with-job-pty → %e2e-pty-spawn) | はい | 実 PTY に打った前景の sh -c が tty に "tty-read-ready>" を書き、端末出力に届くことを確かめる (READY と同じ種類の値) |
| `expected.stream.contains[1]` | "D01_EDITOR_RETURNED" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY で nshell main を対話起動し、行を PTY に書いて出力を読む (%call-with-job-pty → %e2e-pty-spawn) | はい | PTY に 1 行書くと sh の read が返り、"tty-input:<accepted-input>" と "tty-stderr-ok" が端末出力に届くことを確かめる (RETURNED と同じ種類の値) |
| `expected.exit_code` | 0 | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY で nshell main を対話起動し、行を PTY に書いて出力を読む (%call-with-job-pty → %e2e-pty-spawn) | はい | 前景コマンドの後に exit を書き、%assert-pty-child-exit で終了コード 0 を確かめる |
| `steps[2].contains` | "D01_EDITOR_READY" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY で nshell main を対話起動し、行を PTY に書いて出力を読む (%call-with-job-pty → %e2e-pty-spawn) | はい | シナリオ自身の印を待つ同期。同じテストが "tty-read-ready>" を待ってから入力を書く |
| `steps[5].contains` | "D01_EDITOR_RETURNED" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY で nshell main を対話起動し、行を PTY に書いて出力を読む (%call-with-job-pty → %e2e-pty-spawn) | はい | シナリオ自身の印を待つ同期。同じテストが "tty-stderr-ok" まで読んでから exit を書く |

### D02-approx-pager-tty

`t/scenarios/D02/approx-pager-tty.json` [削除]

シナリオの入口: 実 PTY の対話 REPL (キー入力 → 行エディタ → 送信 → 実行 → 端末への出力、exit/Ctrl-D で終了)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "D02_PAGER_READY" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY で nshell main を対話起動し、行を PTY に書いて出力を読む (%call-with-job-pty → %e2e-pty-spawn) | はい | 実 PTY に打った前景の sh -c が tty に "tty-read-ready>" を書き、端末出力に届くことを確かめる (READY と同じ種類の値) |
| `expected.stream.contains[1]` | "D02_PAGER_RETURNED" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY で nshell main を対話起動し、行を PTY に書いて出力を読む (%call-with-job-pty → %e2e-pty-spawn) | はい | PTY に 1 行書くと sh の read が返り、"tty-input:<accepted-input>" と "tty-stderr-ok" が端末出力に届くことを確かめる (RETURNED と同じ種類の値) |
| `expected.exit_code` | 0 | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY で nshell main を対話起動し、行を PTY に書いて出力を読む (%call-with-job-pty → %e2e-pty-spawn) | はい | 前景コマンドの後に exit を書き、%assert-pty-child-exit で終了コード 0 を確かめる |
| `steps[2].contains` | "D02_PAGER_READY" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY で nshell main を対話起動し、行を PTY に書いて出力を読む (%call-with-job-pty → %e2e-pty-spawn) | はい | シナリオ自身の印を待つ同期。同じテストが "tty-read-ready>" を待ってから入力を書く |
| `steps[5].contains` | "D02_PAGER_RETURNED" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY で nshell main を対話起動し、行を PTY に書いて出力を読む (%call-with-job-pty → %e2e-pty-spawn) | はい | シナリオ自身の印を待つ同期。同じテストが "tty-stderr-ok" まで読んでから exit を書く |

### D03-approx-monitor-tty

`t/scenarios/D03/approx-monitor-tty.json` [削除]

シナリオの入口: 実 PTY の対話 REPL (キー入力 → 行エディタ → 送信 → 実行 → 端末への出力、exit/Ctrl-D で終了)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "D03_MONITOR_READY" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY で nshell main を対話起動し、行を PTY に書いて出力を読む (%call-with-job-pty → %e2e-pty-spawn) | はい | 実 PTY に打った前景の sh -c が tty に "tty-read-ready>" を書き、端末出力に届くことを確かめる (READY と同じ種類の値) |
| `expected.stream.contains[1]` | "D03_MONITOR_RETURNED" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY で nshell main を対話起動し、行を PTY に書いて出力を読む (%call-with-job-pty → %e2e-pty-spawn) | はい | PTY に 1 行書くと sh の read が返り、"tty-input:<accepted-input>" と "tty-stderr-ok" が端末出力に届くことを確かめる (RETURNED と同じ種類の値) |
| `expected.exit_code` | 0 | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY で nshell main を対話起動し、行を PTY に書いて出力を読む (%call-with-job-pty → %e2e-pty-spawn) | はい | 前景コマンドの後に exit を書き、%assert-pty-child-exit で終了コード 0 を確かめる |
| `steps[2].contains` | "D03_MONITOR_READY" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY で nshell main を対話起動し、行を PTY に書いて出力を読む (%call-with-job-pty → %e2e-pty-spawn) | はい | シナリオ自身の印を待つ同期。同じテストが "tty-read-ready>" を待ってから入力を書く |
| `steps[5].contains` | "D03_MONITOR_RETURNED" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY で nshell main を対話起動し、行を PTY に書いて出力を読む (%call-with-job-pty → %e2e-pty-spawn) | はい | シナリオ自身の印を待つ同期。同じテストが "tty-stderr-ok" まで読んでから exit を書く |

### D04-approx-remote-tty

`t/scenarios/D04/approx-remote-tty.json` [削除]

シナリオの入口: 実 PTY の対話 REPL (キー入力 → 行エディタ → 送信 → 実行 → 端末への出力、exit/Ctrl-D で終了)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "D04_REMOTE_READY" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY で nshell main を対話起動し、行を PTY に書いて出力を読む (%call-with-job-pty → %e2e-pty-spawn) | はい | 実 PTY に打った前景の sh -c が tty に "tty-read-ready>" を書き、端末出力に届くことを確かめる (READY と同じ種類の値) |
| `expected.stream.contains[1]` | "D04_REMOTE_RETURNED" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY で nshell main を対話起動し、行を PTY に書いて出力を読む (%call-with-job-pty → %e2e-pty-spawn) | はい | PTY に 1 行書くと sh の read が返り、"tty-input:<accepted-input>" と "tty-stderr-ok" が端末出力に届くことを確かめる (RETURNED と同じ種類の値) |
| `expected.exit_code` | 0 | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY で nshell main を対話起動し、行を PTY に書いて出力を読む (%call-with-job-pty → %e2e-pty-spawn) | はい | 前景コマンドの後に exit を書き、%assert-pty-child-exit で終了コード 0 を確かめる |
| `steps[2].contains` | "D04_REMOTE_READY" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY で nshell main を対話起動し、行を PTY に書いて出力を読む (%call-with-job-pty → %e2e-pty-spawn) | はい | シナリオ自身の印を待つ同期。同じテストが "tty-read-ready>" を待ってから入力を書く |
| `steps[5].contains` | "D04_REMOTE_RETURNED" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY で nshell main を対話起動し、行を PTY に書いて出力を読む (%call-with-job-pty → %e2e-pty-spawn) | はい | シナリオ自身の印を待つ同期。同じテストが "tty-stderr-ok" まで読んでから exit を書く |

### D05-approx-fzf-tty

`t/scenarios/D05/approx-fzf-tty.json` [削除]

シナリオの入口: 実 PTY の対話 REPL (キー入力 → 行エディタ → 送信 → 実行 → 端末への出力、exit/Ctrl-D で終了)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "D05_FZF_READY" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY で nshell main を対話起動し、行を PTY に書いて出力を読む (%call-with-job-pty → %e2e-pty-spawn) | はい | 実 PTY に打った前景の sh -c が tty に "tty-read-ready>" を書き、端末出力に届くことを確かめる (READY と同じ種類の値) |
| `expected.stream.contains[1]` | "D05_FZF_RETURNED" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY で nshell main を対話起動し、行を PTY に書いて出力を読む (%call-with-job-pty → %e2e-pty-spawn) | はい | PTY に 1 行書くと sh の read が返り、"tty-input:<accepted-input>" と "tty-stderr-ok" が端末出力に届くことを確かめる (RETURNED と同じ種類の値) |
| `expected.exit_code` | 0 | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY で nshell main を対話起動し、行を PTY に書いて出力を読む (%call-with-job-pty → %e2e-pty-spawn) | はい | 前景コマンドの後に exit を書き、%assert-pty-child-exit で終了コード 0 を確かめる |
| `steps[2].contains` | "D05_FZF_READY" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY で nshell main を対話起動し、行を PTY に書いて出力を読む (%call-with-job-pty → %e2e-pty-spawn) | はい | シナリオ自身の印を待つ同期。同じテストが "tty-read-ready>" を待ってから入力を書く |
| `steps[5].contains` | "D05_FZF_RETURNED" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY で nshell main を対話起動し、行を PTY に書いて出力を読む (%call-with-job-pty → %e2e-pty-spawn) | はい | シナリオ自身の印を待つ同期。同じテストが "tty-stderr-ok" まで読んでから exit を書く |

### D06-approx-editor-child-tty

`t/scenarios/D06/approx-editor-child-tty.json` [残す]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "D06_GIT_EDITOR_READY" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 直接の子 sh が read の前に出す印に当たる: tty-read-ready> が実 PTY に届くことを expect している。 |
| `expected.stream.contains[1]` | "D06_COMMIT_MESSAGE_ACCEPTED" | なし | 孫の sh (editor.sh) が制御端末から read して返ることに当たる。JC149 は直接の子の read だけを試し、孫が前景グループで tty を読むことを確かめるテストはない。 |
| `expected.stream.contains[2]` | "D06_EDITOR_SAVED" | なし | 孫の read が返った後に子が出す印。孫の tty 読み込みに依存するので、上と同じく対応するテストがない。 |
| `expected.exit_code` | 0 | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | exit を打った後に %assert-pty-child-exit (`t/e2e/test-smoke.lisp:266`) で子の終了コード 0 を expect している。 |
| `steps[2].contains` | "D06_GIT_EDITOR_READY" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 同期待ち: tty-read-ready> を待ってから入力を書く同じ同期を expect している。 |
| `steps[5].contains` | "D06_EDITOR_SAVED" | なし | 孫の read が返ったことを待つ同期。孫の tty 読み込みを試すテストがないので対応しない。 |

### D07-approx-password-tty

`t/scenarios/D07/approx-password-tty.json` [削除]

シナリオの入口: 実 PTY 上の対話 REPL (キー入力 → 行エディタ → Enter で実行 → 端末への出力)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "D07_PASSWORD_READY" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY 上で起動した対話 nshell (%e2e-pty-spawn、キーのバイトを PTY に書いて出力を読む) | はい | 前景の sh が tty-read-ready> を出して tty を read するコマンドを PTY に打ち、その出力を確かめている (D07_PASSWORD_READY の代わりのマーカー)。 |
| `expected.stream.contains[1]` | "D07_PASSWORD_RETURNED" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY 上で起動した対話 nshell (%e2e-pty-spawn、キーのバイトを PTY に書いて出力を読む) | はい | PTY に accepted-input と改行を書くと read が返り、その後の tty-input:<accepted-input> が届くことを確かめている (D07_PASSWORD_RETURNED の代わり)。 |
| `expected.exit_code` | 0 | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY 上で起動した対話 nshell (%e2e-pty-spawn、キーのバイトを PTY に書いて出力を読む) | はい | exit を打った後に %assert-pty-child-exit (`t/e2e/test-smoke.lisp:266`) で子の終了コード 0 を確かめている。 |
| `steps[2].contains` | "D07_PASSWORD_READY" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY 上で起動した対話 nshell (%e2e-pty-spawn、キーのバイトを PTY に書いて出力を読む) | はい | tty-read-ready> を待ってから入力を書く同じ同期手順で、その出力を確かめている。 |
| `steps[5].contains` | "D07_PASSWORD_RETURNED" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY 上で起動した対話 nshell (%e2e-pty-spawn、キーのバイトを PTY に書いて出力を読む) | はい | read の後の tty-input:<…> と tty-stderr-ok まで読み、届くことを確かめている。 |

### D08-approx-repl-tty

`t/scenarios/D08/approx-repl-tty.json` [削除]

シナリオの入口: 実 PTY 上の対話 REPL (キー入力 → 行エディタ → Enter で実行 → 端末への出力)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "D08_REPL_READY" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY 上で起動した対話 nshell (%e2e-pty-spawn、キーのバイトを PTY に書いて出力を読む) | はい | 前景の sh が tty-read-ready> を出して tty を read するコマンドを PTY に打ち、その出力を確かめている (D08_REPL_READY の代わりのマーカー)。 |
| `expected.stream.contains[1]` | "D08_REPL_RETURNED" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY 上で起動した対話 nshell (%e2e-pty-spawn、キーのバイトを PTY に書いて出力を読む) | はい | PTY に accepted-input と改行を書くと read が返り、その後の tty-input:<accepted-input> が届くことを確かめている (D08_REPL_RETURNED の代わり)。 |
| `expected.exit_code` | 0 | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY 上で起動した対話 nshell (%e2e-pty-spawn、キーのバイトを PTY に書いて出力を読む) | はい | exit を打った後に %assert-pty-child-exit (`t/e2e/test-smoke.lisp:266`) で子の終了コード 0 を確かめている。 |
| `steps[2].contains` | "D08_REPL_READY" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY 上で起動した対話 nshell (%e2e-pty-spawn、キーのバイトを PTY に書いて出力を読む) | はい | tty-read-ready> を待ってから入力を書く同じ同期手順で、その出力を確かめている。 |
| `steps[5].contains` | "D08_REPL_RETURNED" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY 上で起動した対話 nshell (%e2e-pty-spawn、キーのバイトを PTY に書いて出力を読む) | はい | read の後の tty-input:<…> と tty-stderr-ok まで読み、届くことを確かめている。 |

### D10-approx-container-tty

`t/scenarios/D10/approx-container-tty.json` [削除]

シナリオの入口: 実 PTY 上の対話 REPL (キー入力 → 行エディタ → Enter で実行 → 端末への出力)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "D10_CONTAINER_READY" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY 上で起動した対話 nshell (%e2e-pty-spawn、キーのバイトを PTY に書いて出力を読む) | はい | 前景の sh が tty-read-ready> を出して tty を read するコマンドを PTY に打ち、その出力を確かめている (D10_CONTAINER_READY の代わりのマーカー)。 |
| `expected.stream.contains[1]` | "D10_CONTAINER_RETURNED" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY 上で起動した対話 nshell (%e2e-pty-spawn、キーのバイトを PTY に書いて出力を読む) | はい | PTY に accepted-input と改行を書くと read が返り、その後の tty-input:<accepted-input> が届くことを確かめている (D10_CONTAINER_RETURNED の代わり)。 |
| `expected.exit_code` | 0 | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY 上で起動した対話 nshell (%e2e-pty-spawn、キーのバイトを PTY に書いて出力を読む) | はい | exit を打った後に %assert-pty-child-exit (`t/e2e/test-smoke.lisp:266`) で子の終了コード 0 を確かめている。 |
| `steps[2].contains` | "D10_CONTAINER_READY" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY 上で起動した対話 nshell (%e2e-pty-spawn、キーのバイトを PTY に書いて出力を読む) | はい | tty-read-ready> を待ってから入力を書く同じ同期手順で、その出力を確かめている。 |
| `steps[5].contains` | "D10_CONTAINER_RETURNED" | `t/e2e/test-job-control.lisp:149` it "e2e-external-command-tty-input-and-live-output" | 実 PTY 上で起動した対話 nshell (%e2e-pty-spawn、キーのバイトを PTY に書いて出力を読む) | はい | read の後の tty-input:<…> と tty-stderr-ok まで読み、届くことを確かめている。 |

### D12-ctrl-c-stops-foreground-child

`t/scenarios/D12/ctrl-c-stops-foreground-child.json` [削除 (先にテストを足す)]

シナリオの入口: 実 PTY 上の対話 REPL (キー入力 → 行エディタ → Enter で実行 → 端末への出力)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "D12_CHILD_STOPPED" | `t/e2e/test-smoke.lisp:532` it "e2e-main-interactive-pty-ctrl-c-recovers-foreground-command" | 実 PTY 上で起動した対話 nshell (%e2e-pty-spawn、キーのバイトを PTY に書いて出力を読む) | はい | Ctrl-C の後に打った printf の after-ctrl-c:<130> を確かめており、次のコマンドが動くことは確かめるが、前景は exec sleep の 1 プロセスで、cat input.txt の出力 D12_CHILD_STOPPED は確かめていない。 |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:532` it "e2e-main-interactive-pty-ctrl-c-recovers-foreground-command" | 実 PTY 上で起動した対話 nshell (%e2e-pty-spawn、キーのバイトを PTY に書いて出力を読む) | はい | exit 後に %assert-pty-child-exit で終了コード 0 を確かめている。 |
| `steps[2].contains` | "D12_CHILD_STARTED" | `t/e2e/test-smoke.lisp:532` it "e2e-main-interactive-pty-ctrl-c-recovers-foreground-command" | 実 PTY 上で起動した対話 nshell (%e2e-pty-spawn、キーのバイトを PTY に書いて出力を読む) | はい | ctrl-c-foreground-ready を待っているが、sh が子の sleep を待つ (exec しない) 形ではない。 |
| `steps[6].contains` | "D12_CHILD_STOPPED" | `t/e2e/test-smoke.lisp:532` it "e2e-main-interactive-pty-ctrl-c-recovers-foreground-command" | 実 PTY 上で起動した対話 nshell (%e2e-pty-spawn、キーのバイトを PTY に書いて出力を読む) | はい | Ctrl-C 後の次のコマンドの出力を待つ点は同じだが、値と前景プロセスの形が違う。 |

### E02-bg-resumes-stopped-descendant

`t/scenarios/E02/bg-resumes-stopped-descendant.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "E02_BG_CHILD_STARTED_1" | `t/e2e/test-job-control.lisp:163` it "e2e-external-job-stop-bg-fg-interrupt" | 前景で起動した sh -c が出す印 job-single:<pid> が実 PTY に届き、そのプロセスが前景グループにあることを expect している。 |
| `expected.stream.contains[1]` | "E02_BG_RETURNED_1" | `t/e2e/test-job-control.lisp:163` it "e2e-external-job-stop-bg-fg-interrupt" | Ctrl-Z で止めたジョブに bg 1 を打った後、続く jobs が [1] Running を出す (bg の後に次のコマンドが動く) ことを expect している。%1 の形の解釈は `t/unit/test-builtins-core.lisp:753` が扱う。 |
| `expected.stream.contains[2]` | "E02_BG_CHILD_REAPED_1" | なし | bg で再開した後に孫の sleep 3 まで動き、sh の wait が返ってファイルを書くことに当たる。`t/unit/test-manage-job.lisp:595` は process-continue-group を差し替えた呼び出し確認だけで、T3-R03 は fg の経路なので、bg で孫が再開することを確かめるテストはない。 |
| `expected.stream.contains[3]` | "E02_BG_DESCENDANT_REAPED_1" | `t/e2e/test-job-control.lisp:163` it "e2e-external-job-stop-bg-fg-interrupt" | シナリオ自身が最後に出す同期の印。bg の後に打った行が実行されることを JC163 が jobs と printf の出力で expect している。 |
| `expected.exit_code` | 0 | `t/e2e/test-job-control.lisp:163` it "e2e-external-job-stop-bg-fg-interrupt" | exit 0 の後に %assert-pty-child-exit で終了コード 0 を expect している。 |
| `expected.side_effects.files[0].path` | "e02-bg-child.txt" | なし | 孫の再開後に sh が書くファイル。bg 経路で孫まで再開することを確かめるテストはない。 |
| `expected.side_effects.files[0].equals` | "E02_BG_CHILD_REAPED_1" | なし | 上と同じ。ファイル内容 E02_BG_CHILD_REAPED_1 は孫の sleep が終わり wait が返ったときだけ書かれる。 |
| `steps[2].contains` | "E02_BG_CHILD_STARTED_1" | `t/e2e/test-job-control.lisp:163` it "e2e-external-job-stop-bg-fg-interrupt" | 同期待ち: 前景ジョブの印を待ってから Ctrl-Z を送る同じ同期を expect している。 |
| `steps[6].contains` | "E02_BG_RETURNED_1" | `t/e2e/test-job-control.lisp:163` it "e2e-external-job-stop-bg-fg-interrupt" | bg 1 の後の jobs と printf の出力 job-running-list-end が届くことを expect している。 |
| `steps[9].contains` | "E02_BG_DESCENDANT_REAPED_1" | `t/e2e/test-job-control.lisp:163` it "e2e-external-job-stop-bg-fg-interrupt" | シナリオ自身の同期の印。bg の後の行が実行されることを JC163 が expect している。 |

### E02-fg-bg-and-jobs

`t/scenarios/E02/fg-bg-and-jobs.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "E02_STARTED_2" | `t/e2e/test-job-control.lisp:163` it "e2e-external-job-stop-bg-fg-interrupt" | 同期の印: 前景の sh -c が出す印が実 PTY に届くことを expect している。 |
| `expected.stream.contains[1]` | "E02_STOPPED_JOBS_3" | `t/e2e/test-job-control.lisp:163` it "e2e-external-job-stop-bg-fg-interrupt" | Ctrl-Z の後に打った jobs と printf が実行され、job-stopped-list-end が届くことを expect している。 |
| `expected.stream.contains[2]` | "E02_BG_JOBS_4" | `t/e2e/test-job-control.lisp:163` it "e2e-external-job-stop-bg-fg-interrupt" | bg 1 と jobs の後の printf の出力 job-running-list-end が届くことを expect している。 |
| `expected.stream.contains[3]` | "E02_FG_RETURNED_5" | `t/e2e/test-smoke.lisp:611` it "e2e-main-interactive-pty-job-control-lifecycle" | バックグラウンドで動くジョブを fg 1 で前景に戻し、完了後に続く printf E2E_FG_7 が出ることを expect している。 |
| `expected.exit_code` | 0 | `t/e2e/test-job-control.lisp:163` it "e2e-external-job-stop-bg-fg-interrupt" | exit 0 の後に %assert-pty-child-exit で 0 を expect している。 |
| `expected.side_effects.files[0].path` | "e02-stopped.txt" | `t/e2e/test-job-control.lisp:163` it "e2e-external-job-stop-bg-fg-interrupt" | 停止後の jobs の出力に当たる。JC163 はリダイレクトせず PTY 上で読むが、同じ jobs の出力を expect している。 |
| `expected.side_effects.files[0].contains[0]` | "Stopped" | `t/e2e/test-job-control.lisp:163` it "e2e-external-job-stop-bg-fg-interrupt" | Ctrl-Z で実プロセスを止めた後の jobs の出力に [1] Stopped があることを expect している。 |
| `expected.side_effects.files[0].contains[1]` | "sleep 5" | なし | 前景で起動して止めたジョブの一覧にコマンド文字列 (sleep 5 を含む) が出ることを確かめるテストはない。JC163 は [1] Stopped だけを見て、`t/unit/test-builtins-jobs.lisp:49` は make-test-job で作った Created 状態のジョブだけを見る。 |
| `expected.side_effects.files[1].path` | "e02-running.txt" | `t/e2e/test-job-control.lisp:163` it "e2e-external-job-stop-bg-fg-interrupt" | bg 後の jobs の出力に当たる。JC163 は同じ jobs の出力を PTY 上で expect している。 |
| `expected.side_effects.files[1].contains[0]` | "Running" | `t/e2e/test-job-control.lisp:163` it "e2e-external-job-stop-bg-fg-interrupt" | bg 1 の後の jobs の出力に [1] Running があることを expect している。 |
| `expected.side_effects.files[1].contains[1]` | "sleep 5" | なし | 前景で起動し bg で再開したジョブの一覧のコマンド文字列を確かめるテストはない。SM611 の Running /bin/sleep 3 は & で起動したジョブで、登録経路が違う。 |
| `expected.side_effects.files[2].path` | "e02-child.txt" | なし | 止めて bg・fg した実ジョブが最後まで走ってファイルを書くことを確かめるテストはない。JC163 は fg の後に Ctrl-C で終わらせ、SM611 は止めていないジョブを fg する。 |
| `expected.side_effects.files[2].equals` | "E02_CHILD_DONE" | なし | 上と同じ。E02_CHILD_DONE は再開したジョブが完了したときだけ書かれる。 |
| `expected.side_effects.files[3].path` | "e02-final-jobs.txt" | なし | fg したジョブの完了後の jobs の出力。SM611 は fg 1 の後の一覧からそのジョブが消えたことを見ない。 |
| `expected.side_effects.files[3].equals` | "" | なし | fg で完了したジョブが一覧から消え、jobs の出力が空になることを確かめるテストはない。 |
| `steps[2].contains` | "E02_STARTED_2" | `t/e2e/test-job-control.lisp:163` it "e2e-external-job-stop-bg-fg-interrupt" | 同期待ち: 前景ジョブの印を待ってから Ctrl-Z を送る同じ同期を expect している。 |
| `steps[6].contains` | "E02_STOPPED_JOBS_3" | `t/e2e/test-job-control.lisp:163` it "e2e-external-job-stop-bg-fg-interrupt" | Ctrl-Z 後の jobs と printf の出力 job-stopped-list-end が届くことを expect している。 |
| `steps[9].contains` | "E02_BG_JOBS_4" | `t/e2e/test-job-control.lisp:163` it "e2e-external-job-stop-bg-fg-interrupt" | bg 1 の後の jobs と printf の出力 job-running-list-end が届くことを expect している。 |
| `steps[12].contains` | "E02_FG_RETURNED_5" | `t/e2e/test-smoke.lisp:611` it "e2e-main-interactive-pty-job-control-lifecycle" | fg 1 で前景に戻したジョブの完了後に続く printf の出力 E2E_FG_7 が届くことを expect している。 |

### E03-kill-percent-one

`t/scenarios/E03/kill-percent-one.json` [golden へ移す]

```json
{
  "env": {},
  "expected": {
    "duration_ms": 0,
    "effects": [],
    "nshell_api": 1,
    "ok": true,
    "safety": {
      "level": "confirm",
      "reasons": [
        {
          "rule": "classify/unknown-command",
          "text": "unknown command"
        }
      ]
    },
    "state": {
      "cwd": "$WORK",
      "env_changed": [],
      "jobs": []
    },
    "status": 0,
    "stderr": {
      "bytes": 0,
      "lines": 0,
      "text": "",
      "truncated": false
    },
    "stdout": {
      "bytes": 11,
      "lines": 1,
      "text": "E03_KILLED\n",
      "truncated": false
    }
  },
  "files": {},
  "input": "sleep 5 & kill %1; wait %1; test $? -ne 0 && jobs && echo E03_KILLED"
}
```

この期待値は、aarch64-darwin でビルドした nshell に、golden の実行器と同じ作業ディレクトリ・環境・正規化で 3 回流し、`error.message` を除いた envelope 全体が 3 回とも一致したものです。Linux では流していません。

### E04-disown-removes-job

`t/scenarios/E04/disown-removes-job.json` [golden へ移す]

```json
{
  "env": {},
  "expected": {
    "duration_ms": 0,
    "effects": [],
    "nshell_api": 1,
    "ok": true,
    "safety": {
      "level": "confirm",
      "reasons": [
        {
          "rule": "classify/unknown-command",
          "text": "unknown command"
        }
      ]
    },
    "state": {
      "cwd": "$WORK",
      "env_changed": [],
      "jobs": []
    },
    "status": 0,
    "stderr": {
      "bytes": 0,
      "lines": 0,
      "text": "",
      "truncated": false
    },
    "stdout": {
      "bytes": 34,
      "lines": 2,
      "text": "[1] Running sleep 30\nE04_DISOWNED\n",
      "truncated": false
    }
  },
  "files": {},
  "input": "sleep 30 & jobs; disown %1; jobs; kill $!; echo E04_DISOWNED"
}
```

この期待値は、aarch64-darwin でビルドした nshell に、golden の実行器と同じ作業ディレクトリ・環境・正規化で 3 回流し、`error.message` を除いた envelope 全体が 3 回とも一致したものです。Linux では流していません。

### E05-wait-collects-background-status

`t/scenarios/E05/wait-collects-background-status.json` [golden へ移す]

```json
{
  "env": {},
  "expected": {
    "duration_ms": 0,
    "effects": [
      {
        "kind": "writes",
        "path": "e05-child.txt"
      },
      {
        "kind": "reads",
        "path": "e05-child.txt"
      }
    ],
    "nshell_api": 1,
    "ok": true,
    "safety": {
      "level": "confirm",
      "reasons": [
        {
          "rule": "classify/opaque-wrapper",
          "text": "the command this wrapper runs cannot be checked"
        },
        {
          "rule": "classify/output-redirect",
          "text": "output redirection or process substitution requires confirmation"
        },
        {
          "rule": "classify/unknown-command",
          "text": "unknown command"
        }
      ]
    },
    "state": {
      "cwd": "$WORK",
      "env_changed": [],
      "jobs": []
    },
    "status": 0,
    "stderr": {
      "bytes": 0,
      "lines": 0,
      "text": "",
      "truncated": false
    },
    "stdout": {
      "bytes": 14,
      "lines": 1,
      "text": "E05_CHILD_DONE",
      "truncated": false
    }
  },
  "files": {},
  "input": "sh -c 'printf E05_CHILD_DONE > e05-child.txt; exit 7' & wait %1; test $? -eq 7 && cat e05-child.txt && jobs"
}
```

この期待値は、aarch64-darwin でビルドした nshell に、golden の実行器と同じ作業ディレクトリ・環境・正規化で 3 回流し、`error.message` を除いた envelope 全体が 3 回とも一致したものです。Linux では流していません。

### E06-completion-notification-and-removal

`t/scenarios/E06/completion-notification-and-removal.json` [削除 (先にテストを足す)]

シナリオの入口: 実 PTY 上の対話 REPL (キー入力 → 行エディタ → Enter で実行 → 端末への出力)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "Done" | `t/e2e/test-smoke.lisp:611` it "e2e-main-interactive-pty-job-control-lifecycle" | 実 PTY 上で起動した対話 nshell (%e2e-pty-spawn、キーのバイトを PTY に書いて出力を読む) | はい | /bin/sleep 2 & の完了通知 Done /bin/sleep 2 がちょうど 1 回出ることを確かめている。 |
| `expected.stream.contains[1]` | "E06_WORK_DONE_6" | `t/e2e/test-smoke.lisp:611` it "e2e-main-interactive-pty-job-control-lifecycle" | 実 PTY 上で起動した対話 nshell (%e2e-pty-spawn、キーのバイトを PTY に書いて出力を読む) | はい | 前景の /bin/sleep 3; jobs; printf E2E_BACKGROUND_5 のマーカーを待つ (E06_WORK_DONE_6 の代わり)。 |
| `expected.stream.contains[2]` | "E06_AFTER_DONE_7" | `t/e2e/test-smoke.lisp:611` it "e2e-main-interactive-pty-job-control-lifecycle" | 実 PTY 上で起動した対話 nshell (%e2e-pty-spawn、キーのバイトを PTY に書いて出力を読む) | はい | jobs; printf E2E_JOBS_CAPTURED_7 のマーカーを待つ (E06_AFTER_DONE_7 の代わり)。 |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:611` it "e2e-main-interactive-pty-job-control-lifecycle" | 実 PTY 上で起動した対話 nshell (%e2e-pty-spawn、キーのバイトを PTY に書いて出力を読む) | はい | exit 後に %assert-pty-child-exit で終了コード 0 を確かめている。 |
| `expected.side_effects.files[0].path` | "completed-jobs.txt" | `t/unit/test-repl-background.lisp:114` it "reap-background-jobs-notifies-and-retains-completed-status" | reap-background-jobs をスタブしたプロセス状態で直接呼ぶ (PTY・jobs 実行なし) | いいえ | reap-background-jobs を 2 回直接呼び、2 回目の通知が空であることを確かめるだけで、jobs > completed-jobs.txt のファイルは作らない。 |
| `expected.side_effects.files[0].exists` | true | `t/unit/test-repl-background.lisp:114` it "reap-background-jobs-notifies-and-retains-completed-status" | reap-background-jobs をスタブしたプロセス状態で直接呼ぶ (PTY・jobs 実行なし) | いいえ | ファイルの存在は確かめていない。 |
| `expected.side_effects.files[0].equals` | "" | `t/unit/test-repl-background.lisp:114` it "reap-background-jobs-notifies-and-retains-completed-status" | reap-background-jobs をスタブしたプロセス状態で直接呼ぶ (PTY・jobs 実行なし) | いいえ | 完了ジョブを回収した後に jobs をファイルへリダイレクトした内容が空であることは確かめていない (e2e 側も jobs の出力に Done/Running が含まれないことだけを見る)。 |
| `steps[4].contains` | "E06_WORK_DONE_6" | `t/e2e/test-smoke.lisp:611` it "e2e-main-interactive-pty-job-control-lifecycle" | 実 PTY 上で起動した対話 nshell (%e2e-pty-spawn、キーのバイトを PTY に書いて出力を読む) | はい | 前景コマンドのマーカーを待つ同じ同期手順 (値は違う)。 |
| `steps[7].contains` | "E06_AFTER_DONE_7" | `t/e2e/test-smoke.lisp:611` it "e2e-main-interactive-pty-job-control-lifecycle" | 実 PTY 上で起動した対話 nshell (%e2e-pty-spawn、キーのバイトを PTY に書いて出力を読む) | はい | jobs の後のマーカーを待つ同じ同期手順 (値は違う)。 |

### E07-pipeline-is-one-stopped-job

`t/scenarios/E07/pipeline-is-one-stopped-job.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "E07_STARTED_5" | `t/e2e/test-job-control.lisp:165` it "e2e-external-pipeline-stop-bg-fg-interrupt" | 3 段のパイプラインを打ち、各段が出す job-left/middle/right の印を待ち、3 つの pid が 1 つのプロセスグループにあることを確かめる (75-97 行)。止める前にパイプラインが動いて出力することを最後まで駆動している。PTY が使えない nix サンドボックスでは skip される |
| `expected.stream.contains[1]` | "E07_JOBS_CAPTURED_7" | なし | 止まったジョブを kill %1; wait %1 で終わらせたあとシェルが続くことを確かめるテストはない。e2e は bg/fg/割り込みで終える |
| `expected.stream.contains[2]` | "E07_AFTER_2" | なし | そのあとのコマンドが動くことを待つ。同じく対応するテストはない |
| `expected.exit_code` | 0 | `t/unit/test-repl-execution.lisp:12` it "repl-installed-terminal-controls-actual-runner-lifecycle" | render-prompt-cont が +repl-exit+ を返して REPL が終わると run-repl が 0 を返すことを :success の場合で確かめる (exit 組み込みで +repl-exit+ に至ることは `t/unit/test-repl-state.lisp:255` が確かめる)。セッションを exit で終えて 0 になる流れを最後まで駆動している |
| `expected.side_effects.files[0].path` | "stopped-pipeline-jobs.txt" | なし | jobs の出力をファイルへリダイレクトすること。REPL で jobs を > で書くテストはない |
| `expected.side_effects.files[0].contains[0]` | "Stopped" | `t/e2e/test-job-control.lisp:165` it "e2e-external-pipeline-stop-bg-fg-interrupt" | Ctrl-Z (code 26) を送り全段が T 状態になるのを待ってから jobs を実行し、出力が "[1] Stopped" を含むことを確かめる (109-119 行)。PTY が使えない nix サンドボックスでは skip される |
| `expected.side_effects.files[0].contains[1]` | "\| cat" | なし | ジョブ一覧にパイプライン全体のコマンド文字列 ("\| cat") が出ること。e2e は確かめず、`t/unit/test-manage-job.lisp:319` は単一コマンド "echo hello" の一覧だけ |
| `expected.side_effects.files[1].path` | "stopped-pipeline-count.txt" | なし | grep -c の結果をファイルへ書くこと。対応するテストはない |
| `expected.side_effects.files[1].equals` | "1\n" | なし | Stopped 行が 1 つだけ (パイプラインが 1 つのジョブとして登録される) こと。e2e は search で "[1] Stopped" の有無を見るだけで、行数は確かめていない |
| `steps[2].contains` | "E07_STARTED_5" | `t/e2e/test-job-control.lisp:165` it "e2e-external-pipeline-stop-bg-fg-interrupt" | 3 段のパイプラインを打ち、各段が出す job-left/middle/right の印を待ち、3 つの pid が 1 つのプロセスグループにあることを確かめる (75-97 行)。止める前にパイプラインが動いて出力することを最後まで駆動している。PTY が使えない nix サンドボックスでは skip される |
| `steps[5].contains` | "E07_JOBS_CAPTURED_$((3+4))" | `t/e2e/test-job-control.lisp:165` it "e2e-external-pipeline-stop-bg-fg-interrupt" | Ctrl-Z のあと端末の前面プロセスグループがシェルに戻るのを待ち (110-114 行)、次の入力 jobs を受け付けることを確かめる。入力を待つ同期として同じ流れを駆動している |
| `steps[7].contains` | "E07_JOBS_CAPTURED_7" | なし | kill %1; wait %1 のあとの echo の出力を待つ同期。対応するテストはない |
| `steps[10].contains` | "E07_AFTER_2" | なし | 後続コマンドの出力を待つ同期。対応するテストはない |

### E08-ctrl-c-interrupts-whole-pipeline

`t/scenarios/E08/ctrl-c-interrupts-whole-pipeline.json` [残す]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "E08_PIPELINE_STARTED_8" | `t/e2e/test-smoke.lisp:683` it "e2e-main-interactive-pty-foreground-pipeline-ignores-external-command-timeout" | 前景の sh -c '...' \| cat の出力が cat を通って実 PTY に届くことを expect している。 |
| `expected.stream.contains[1]` | "E08_PIPELINE_STOPPED" | なし | 最初から前景で起動したパイプラインに Ctrl-C を送った後に次のコマンドが動くことに当たる。JC165 は bg・fg で戻したパイプラインに Ctrl-C を送り、SM532 は単一コマンドなので、この組み合わせを確かめるテストはない。 |
| `expected.exit_code` | 0 | `t/e2e/test-job-control.lisp:165` it "e2e-external-pipeline-stop-bg-fg-interrupt" | exit 0 の後に %assert-pty-child-exit で 0 を expect している。 |
| `steps[2].contains` | "E08_PIPELINE_STARTED_8" | `t/e2e/test-smoke.lisp:683` it "e2e-main-interactive-pty-foreground-pipeline-ignores-external-command-timeout" | 同期待ち: パイプラインの出力が届くのを待つ同じ同期を expect している。 |
| `steps[6].contains` | "E08_PIPELINE_STOPPED" | なし | Ctrl-C 後の次のコマンドの出力を待つ同期。上の contains[1] と同じ理由で対応するテストがない。 |

### E09-script-job-state-updates

`t/scenarios/E09/script-job-state-updates.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.contains[0]` | "E09_SCRIPT_DONE_3" | `t/e2e/test-smoke.lisp:387` it "e2e-main-wait-returns-background-status" | バッチ実行で & の実ジョブに wait %1 を当て、その終了コードが返ることを expect している (sh -c 'exit 1' で 1)。シナリオの印は wait が 0 を返したときに出る。 |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:387` it "e2e-main-wait-returns-background-status" | バッチ実行の終了コードが最後の wait の値と等しいことを expect している。 |
| `expected.side_effects.files[0].path` | "e09-before.txt" | なし | スクリプト実行中の jobs の出力。バッチ実行で実ジョブを jobs が一覧に出すことを確かめるテストはない。 |
| `expected.side_effects.files[0].contains[0]` | "Running" | なし | バッチ実行の jobs が実行中の実ジョブを Running と出すことを確かめるテストはない。SM611 は対話 PTY、`t/unit/test-builtins-jobs.lisp:49` は make-test-job の Created 状態だけを見る。 |
| `expected.side_effects.files[0].contains[1]` | "sleep 5" | なし | 同じく、バッチ実行の一覧にコマンド文字列 sleep 5 が出ることを確かめるテストはない。 |
| `expected.side_effects.files[1].path` | "e09-after.txt" | なし | wait %1 の後の jobs の出力。実ジョブを wait した後の一覧を確かめるテストはない。 |
| `expected.side_effects.files[1].exists` | true | なし | 上と同じ。ファイルは wait が 0 を返した後の jobs のリダイレクトでだけ作られる。 |
| `expected.side_effects.files[1].equals` | "" | なし | `t/unit/test-builtins-core.lisp:655` は完了済みにしたテスト用ジョブを wait した後の jobs が空であることを確かめるが、実行中の実ジョブを wait %1 で待った後に一覧から消えることは確かめない (受け入れレビューの指摘どおり)。 |

### F01-approx-cooked-mode-after-crash

`t/scenarios/F01/approx-cooked-mode-after-crash.json` [削除]

シナリオの入口: 実 PTY 上の対話 REPL (キー入力 → 行エディタ → Enter で実行 → 端末への出力)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "F01_COOKED_READY" | `t/scenarios/D11/approx-cooked-mode-after-crash.json:35` [残す] の "D11-approx-cooked-mode-after-crash" expected.stream.contains[0] | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | D11 は同じ crash-terminal.sh と cat after-crash.txt の手順で D11_COOKED_READY を stream に求める。 |
| `expected.stream.contains[1]` | "F01_CANON_OK" | `t/scenarios/D11/approx-cooked-mode-after-crash.json:36` [残す] の "D11-approx-cooked-mode-after-crash" expected.stream.contains[1] | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | D11 は同じ stty -a \| grep icanon の検査で D11_CANON_OK を求める。 |
| `expected.stream.contains[2]` | "F01_ISIG_OK" | `t/scenarios/D11/approx-cooked-mode-after-crash.json:37` [残す] の "D11-approx-cooked-mode-after-crash" expected.stream.contains[2] | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | D11 は同じ isig の検査で D11_ISIG_OK を求める。 |
| `expected.stream.contains[3]` | "F01_ECHO_OK" | `t/scenarios/D11/approx-cooked-mode-after-crash.json:38` [残す] の "D11-approx-cooked-mode-after-crash" expected.stream.contains[3] | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | D11 は同じ echo の検査で D11_ECHO_OK を求める。 |
| `expected.stream.contains[4]` | "F01_CHECK_DONE" | `t/scenarios/D11/approx-cooked-mode-after-crash.json:39` [残す] の "D11-approx-cooked-mode-after-crash" expected.stream.contains[4] | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | D11 は同じ検査の終わりの D11_CHECK_DONE を求める。 |
| `expected.exit_code` | 0 | `t/scenarios/D11/approx-cooked-mode-after-crash.json:42` [残す] の "D11-approx-cooked-mode-after-crash" expected.exit_code | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | D11 も終了コード 0 を求める。 |
| `steps[4].contains` | "F01_COOKED_READY" | `t/scenarios/D11/approx-cooked-mode-after-crash.json:63` [残す] の "D11-approx-cooked-mode-after-crash" steps[4].contains | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | D11 は同じ位置で D11_COOKED_READY を待つ。 |
| `steps[7].contains` | "F01_CHECK_DONE" | `t/scenarios/D11/approx-cooked-mode-after-crash.json:81` [残す] の "D11-approx-cooked-mode-after-crash" steps[8].contains | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | D11 は wait_input を 1 つ挟むので steps[8] で D11_CHECK_DONE を待つ。 |

### F10-unicode-grapheme-cursor-edit

`t/scenarios/F10/unicode-grapheme-cursor-edit.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "AX👩‍💻" | なし | Ctrl-B で 👩‍💻 (U+1F469 U+200D U+1F4BB の 3 符号点) を 1 書記素として左へ越え、そこに X を入れるテストはない。`t/unit/test-east-asian-width.lisp:155` は右移動 (move-cursor-clearing-suggestion +1) と後退削除だけ |
| `expected.exit_code` | 0 | `t/unit/test-repl-execution.lisp:12` it "repl-installed-terminal-controls-actual-runner-lifecycle" | render-prompt-cont が +repl-exit+ を返して REPL が終わると run-repl が 0 を返すことを :success の場合で確かめる (exit 組み込みで +repl-exit+ に至ることは `t/unit/test-repl-state.lisp:255` が確かめる)。セッションを exit で終えて 0 になる流れを最後まで駆動している |
| `steps[4].contains` | "AX👩‍💻" | なし | Ctrl-B で 👩‍💻 (U+1F469 U+200D U+1F4BB の 3 符号点) を 1 書記素として左へ越え、そこに X を入れるテストはない。`t/unit/test-east-asian-width.lisp:155` は右移動 (move-cursor-clearing-suggestion +1) と後退削除だけ。この wait はシナリオ自身の echo の出力を待つ同期でもある |

### F11-16-color-sgr

`t/scenarios/F11/16-color-sgr.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "\u001b[1;94m" | なし | `t/unit/test-theme-style.lisp:135` は (:rgb 95 175 255) を :16 で ESC [94m (太字なし) にすることだけ、`t/unit/test-highlight.lisp:210` は :truecolor の ESC [1;38;2;95;175;255m だけを確かめる。TERM=xterm・COLORTERM 空から :16 を選ぶ判定 (`src/infrastructure/terminal/ansi.lisp:145`) も、太字と 16 色を合わせた ESC [1;94m も確かめていない |
| `expected.exit_code` | 0 | `t/unit/test-repl-execution.lisp:12` it "repl-installed-terminal-controls-actual-runner-lifecycle" | render-prompt-cont が +repl-exit+ を返して REPL が終わると run-repl が 0 を返すことを :success の場合で確かめる (exit 組み込みで +repl-exit+ に至ることは `t/unit/test-repl-state.lisp:255` が確かめる)。セッションを exit で終えて 0 になる流れを最後まで駆動している |
| `steps[1].contains` | "echo \"$F11_MARKER\"" | なし | 入力行 echo "$F11_MARKER" の表示を待つ同期。入力の描画そのものは多くのテストが扱うが、この環境 (色深度判定つき) で描いた入力行を確かめるものはないので add_test (2) の SGR 除去後の等値で確かめる |
| `steps[3].contains` | "F11_COMMAND_OK" | なし | echo "$F11_MARKER" の出力を待つ同期。REPL で "$変数" を echo した出力を確かめるテストは見つからなかった (`t/unit/test-repl-execution.lisp:481` はコマンド位置の展開で別の入力) ので add_test (3) で確かめる |

### F11-256-color-sgr

`t/scenarios/F11/256-color-sgr.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "\u001b[1;38;5;75m" | なし | `t/unit/test-theme-style.lisp:120` は :256 で太字なしの ESC [38;5;Nm だけを、`t/unit/test-highlight.lisp:210` は :truecolor だけを確かめる。TERM=xterm-256color・COLORTERM 空から :256 を選ぶ判定も、ESC [1;38;5;75m も確かめていない |
| `expected.exit_code` | 0 | `t/unit/test-repl-execution.lisp:12` it "repl-installed-terminal-controls-actual-runner-lifecycle" | render-prompt-cont が +repl-exit+ を返して REPL が終わると run-repl が 0 を返すことを :success の場合で確かめる (exit 組み込みで +repl-exit+ に至ることは `t/unit/test-repl-state.lisp:255` が確かめる)。セッションを exit で終えて 0 になる流れを最後まで駆動している |
| `steps[1].contains` | "echo \"$F11_MARKER\"" | なし | 入力行 echo "$F11_MARKER" の表示を待つ同期。入力の描画そのものは多くのテストが扱うが、この環境 (色深度判定つき) で描いた入力行を確かめるものはないので add_test (2) の SGR 除去後の等値で確かめる |
| `steps[3].contains` | "F11_COMMAND_OK" | なし | echo "$F11_MARKER" の出力を待つ同期。REPL で "$変数" を echo した出力を確かめるテストは見つからなかった (`t/unit/test-repl-execution.lisp:481` はコマンド位置の展開で別の入力) ので add_test (3) で確かめる |

### F11-no-color-sgr

`t/scenarios/F11/no-color-sgr.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.excludes[0]` | "\u001b[1;94m" | なし | 色なしの生成は `t/unit/test-theme-style.lisp:167` が ansi-style-sequence :depth :none の等値 (ESC [1m) で確かめるが、NO_COLOR=1 から :none を選ぶ判定 (`src/infrastructure/terminal/ansi.lisp:149`) と、その判定を通った highlight の出力にこの列がないことは確かめていない |
| `expected.stream.excludes[1]` | "\u001b[1;38;5;75m" | なし | 色なしの生成は `t/unit/test-theme-style.lisp:167` が ansi-style-sequence :depth :none の等値 (ESC [1m) で確かめるが、NO_COLOR=1 から :none を選ぶ判定 (`src/infrastructure/terminal/ansi.lisp:149`) と、その判定を通った highlight の出力にこの列がないことは確かめていない |
| `expected.stream.excludes[2]` | "\u001b[1;38;2;95;175;255m" | なし | 色なしの生成は `t/unit/test-theme-style.lisp:167` が ansi-style-sequence :depth :none の等値 (ESC [1m) で確かめるが、NO_COLOR=1 から :none を選ぶ判定 (`src/infrastructure/terminal/ansi.lisp:149`) と、その判定を通った highlight の出力にこの列がないことは確かめていない。COLORTERM=truecolor より NO_COLOR が優先されることも試していない |
| `expected.exit_code` | 0 | `t/unit/test-repl-execution.lisp:12` it "repl-installed-terminal-controls-actual-runner-lifecycle" | render-prompt-cont が +repl-exit+ を返して REPL が終わると run-repl が 0 を返すことを :success の場合で確かめる (exit 組み込みで +repl-exit+ に至ることは `t/unit/test-repl-state.lisp:255` が確かめる)。セッションを exit で終えて 0 になる流れを最後まで駆動している |
| `steps[1].contains` | "echo \"$F11_MARKER\"" | なし | 入力行 echo "$F11_MARKER" の表示を待つ同期。入力の描画そのものは多くのテストが扱うが、この環境 (色深度判定つき) で描いた入力行を確かめるものはないので add_test (2) の SGR 除去後の等値で確かめる |
| `steps[3].contains` | "F11_COMMAND_OK" | なし | echo "$F11_MARKER" の出力を待つ同期。REPL で "$変数" を echo した出力を確かめるテストは見つからなかった (`t/unit/test-repl-execution.lisp:481` はコマンド位置の展開で別の入力) ので add_test (3) で確かめる |

### G01-approx-emacs-case-transform

`t/scenarios/G01/approx-emacs-case-transform.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "BETA" | なし | echo beta に M-b M-u を当てて BETA を出すことに当たる。バッファの変換は reducer テストが確かめるが、どれも input-dispatch-set-binding で直接 bind しており、init.lisp の bind 行を起動時に読んで効かせる経路 (`src/presentation/repl-session-init.lisp:275` で handler を入れた後 :288 で設定を読む) を通すテストはない。 |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY で起動した対話セッションが exit で終了コード 0 になることを expect している。 |
| `steps[4].contains` | "BETA" | なし | BETA の出力を待つ同期。上と同じく、init.lisp の bind を通すテストがない。 |

### G01-approx-emacs-transpose

`t/scenarios/G01/approx-emacs-transpose.json` [削除 (先にテストを足す)]

シナリオの入口: 実 PTY 上の対話 REPL (キー入力 → 行エディタ → Enter で実行 → 端末への出力)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "ba" | `t/unit/test-input-state-commands.lisp:259` it "input-state-ctrl-t-at-eol-transposes-last-two-chars" | 行エディタの reducer を直接呼ぶ (reduce-once、端末・REPL ループ・実行なし) | いいえ | buffer "abcd" で reduce-once :ctrl-t を呼び "abdc" になることだけを確かめ、実行結果の出力 ba は見ていない。 |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY 上で起動した対話 nshell (%e2e-pty-spawn、キーのバイトを PTY に書いて出力を読む) | はい | 実 PTY で exit を打ち終了コード 0 を確かめているが、C-t は打っていない。 |
| `steps[3].contains` | "ba" | `t/unit/test-input-state-commands.lisp:259` it "input-state-ctrl-t-at-eol-transposes-last-two-chars" | 行エディタの reducer を直接呼ぶ (reduce-once、端末・REPL ループ・実行なし) | いいえ | 出力を待つ手順はない。 |

### G01-approx-emacs-word-delete

`t/scenarios/G01/approx-emacs-word-delete.json` [削除 (先にテストを足す)]

シナリオの入口: 実 PTY 上の対話 REPL (キー入力 → 行エディタ → Enter で実行 → 端末への出力)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.side_effects.files[0].path` | "created" | `t/unit/test-input-state-kill-yank.lisp:162` it "input-state-alt-d-kills-next-word" | 行エディタの reducer を直接呼ぶ (reduce-once、端末・REPL ループ・実行なし) | いいえ | buffer "echo   hello world" で reduce-once :alt-d を呼びバッファを確かめるだけで、touch の実行もファイル created も見ていない。 |
| `expected.side_effects.files[0].exists` | true | `t/unit/test-input-state-kill-yank.lisp:162` it "input-state-alt-d-kills-next-word" | 行エディタの reducer を直接呼ぶ (reduce-once、端末・REPL ループ・実行なし) | いいえ | ファイルの存在は確かめていない。 |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY 上で起動した対話 nshell (%e2e-pty-spawn、キーのバイトを PTY に書いて出力を読む) | はい | 実 PTY で exit を打ち終了コード 0 を確かめているが、M-b / M-d は打っていない。 |
| `steps[5].contains` | "G01_2" | `t/unit/test-input-state-kill-yank.lisp:162` it "input-state-alt-d-kills-next-word" | 行エディタの reducer を直接呼ぶ (reduce-once、端末・REPL ループ・実行なし) | いいえ | G01_2 の出力を待つ手順はない。 |

### G01-case-conversion

`t/scenarios/G01/case-conversion.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "G01_UPCASE_OK" | なし | sh checker.sh upcase に M-b M-u を当てて UPCASE にすることに当たる。`t/unit/test-input-state-case-undo.lisp:10` が単語先頭での alt-u を確かめるが、バッファの変換は reducer テストが確かめるが、どれも input-dispatch-set-binding で直接 bind しており、init.lisp の bind 行を起動時に読んで効かせる経路 (`src/presentation/repl-session-init.lisp:275` で handler を入れた後 :288 で設定を読む) を通すテストはない。 |
| `expected.stream.contains[1]` | "G01_DOWNCASE_OK" | なし | LOWER に M-b M-l を当てることに当たる。`t/unit/test-input-state-case-undo.lisp:35` の it-each が alt-l を確かめるが、バッファの変換は reducer テストが確かめるが、どれも input-dispatch-set-binding で直接 bind しており、init.lisp の bind 行を起動時に読んで効かせる経路 (`src/presentation/repl-session-init.lisp:275` で handler を入れた後 :288 で設定を読む) を通すテストはない。 |
| `expected.stream.contains[2]` | "G01_CAPITALIZE_OK" | なし | tITLE に M-b M-c を当てて Title にすることに当たる。`t/unit/test-input-state-case-undo.lisp:35` の it-each が alt-c を確かめるが、バッファの変換は reducer テストが確かめるが、どれも input-dispatch-set-binding で直接 bind しており、init.lisp の bind 行を起動時に読んで効かせる経路 (`src/presentation/repl-session-init.lisp:275` で handler を入れた後 :288 で設定を読む) を通すテストはない。 |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY で起動した対話セッションが exit で終了コード 0 になることを expect している。 |
| `steps[4].contains` | "G01_UPCASE_OK" | なし | G01_UPCASE_OK を待つ同期。init.lisp の bind を通すテストがない。 |
| `steps[9].contains` | "G01_DOWNCASE_OK" | なし | G01_DOWNCASE_OK を待つ同期。init.lisp の bind を通すテストがない。 |
| `steps[14].contains` | "G01_CAPITALIZE_OK" | なし | G01_CAPITALIZE_OK を待つ同期。init.lisp の bind を通すテストがない。 |

### G01-char-transpose

`t/scenarios/G01/char-transpose.json` [削除 (先にテストを足す)]

シナリオの入口: 実 PTY 上の対話 REPL (キー入力 → 行エディタ → Enter で実行 → 端末への出力)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "G01_CHAR_TRANSPOSE_OK" | `t/unit/test-input-state-commands.lisp:259` it "input-state-ctrl-t-at-eol-transposes-last-two-chars" | 行エディタの reducer を直接呼ぶ (reduce-once、端末・REPL ループ・実行なし) | いいえ | reduce-once :ctrl-t のバッファだけを確かめ、checker.sh の実行結果は見ていない。 |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY 上で起動した対話 nshell (%e2e-pty-spawn、キーのバイトを PTY に書いて出力を読む) | はい | 実 PTY で exit を打ち終了コード 0 を確かめているが、C-t は打っていない。 |
| `steps[3].contains` | "G01_CHAR_TRANSPOSE_OK" | `t/unit/test-input-state-commands.lisp:259` it "input-state-ctrl-t-at-eol-transposes-last-two-chars" | 行エディタの reducer を直接呼ぶ (reduce-once、端末・REPL ループ・実行なし) | いいえ | 出力を待つ手順はない。 |

### G01-word-forward-motion

`t/scenarios/G01/word-forward-motion.json` [削除 (先にテストを足す)]

シナリオの入口: 実 PTY 上の対話 REPL (キー入力 → 行エディタ → Enter で実行 → 端末への出力)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "G01_WORD_FORWARD_OK" | `t/unit/test-input-state-navigation.lisp:93` it "input-state-meta-b-and-f-move-by-word" | 行エディタの reducer を直接呼ぶ (reduce-once、端末・REPL ループ・実行なし) | いいえ | reduce-once :alt-b / :alt-f のカーソル位置だけを確かめ、C-k と追記の後の実行結果は見ていない。 |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY 上で起動した対話 nshell (%e2e-pty-spawn、キーのバイトを PTY に書いて出力を読む) | はい | 実 PTY で exit を打ち終了コード 0 を確かめているが、M-b / M-f / C-k は打っていない。 |
| `steps[7].contains` | "G01_COMMAND_FINISHED" | `t/e2e/test-smoke-input.lisp:180` it "e2e-ctrl-k-replaces-line-suffix" | 文字列からキーを復号して reducer に適用し、行を解析するだけ (REPL ループ・実行なし) | いいえ | C-b と C-k の復号と reducer の後の行を解析するだけで、実行して G01_COMMAND_FINISHED を出すことはない。 |

### G01-word-motion-deletion

`t/scenarios/G01/word-motion-deletion.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "G01_WORD_MOTION_DELETE_OK" | `t/scenarios/G02/runtime-vi-toggle.json:51` [残す] の "G02-runtime-vi-toggle" expected.stream.contains[3] | 残す G02-runtime-vi-toggle が、vi を切った後に同じ sh checker-off.sh remove proof へ M-b M-b M-d と Enter を実 PTY で当て、proof だけが残った印を assert している。 |
| `expected.exit_code` | 0 | `t/scenarios/G02/runtime-vi-toggle.json:54` [残す] の "G02-runtime-vi-toggle" expected.exit_code | 残す G02-runtime-vi-toggle が同じ操作を含むセッションの終了コード 0 を assert している。 |
| `steps[4].contains` | "checker.sh  proof" | なし | M-d の後の再描画で画面に "checker.sh  proof" (空白 2 つ) が出ることに当たる。再描画で編集後のバッファが出ることを確かめるテストはない。 |
| `steps[6].contains` | "G01_WORD_MOTION_DELETE_OK" | `t/scenarios/G02/runtime-vi-toggle.json:51` [残す] の "G02-runtime-vi-toggle" expected.stream.contains[3] | 残す G02-runtime-vi-toggle が同じ編集の後の出力 G02_RUNTIME_VI_OFF_OK を assert している。 |

### G01-word-transpose

`t/scenarios/G01/word-transpose.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "G01_WORD_TRANSPOSE_OK" | なし | sh checker.sh second first に M-b M-t を当てて first second にすることに当たる。`t/unit/test-input-state-commands.lisp:403` の it-each ("echo one two" cursor 9 → "echo two one") と `t/e2e/test-smoke-input.lisp:100` が確かめるが、バッファの変換は reducer テストが確かめるが、どれも input-dispatch-set-binding で直接 bind しており、init.lisp の bind 行を起動時に読んで効かせる経路 (`src/presentation/repl-session-init.lisp:275` で handler を入れた後 :288 で設定を読む) を通すテストはない。 |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY で起動した対話セッションが exit で終了コード 0 になることを expect している。 |
| `steps[4].contains` | "G01_WORD_TRANSPOSE_OK" | なし | G01_WORD_TRANSPOSE_OK を待つ同期。init.lisp の bind を通すテストがない。 |

### G02-approx-vi-mode-editing

`t/scenarios/G02/approx-vi-mode-editing.json` [削除 (先にテストを足す)]

シナリオの入口: 実 PTY 上の対話 REPL (キー入力 → 行エディタ → Enter で実行 → 端末への出力)、NSHELL_VI_MODE=1 の vi モード

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "G02_2" | `t/unit/test-input-state-vi.lisp:41` it "vi-i-returns-to-insert-mode" | 行エディタの reducer を直接呼ぶ (reduce-once、端末・REPL ループ・実行なし) | いいえ | vi command 状態の input-state に reduce-once :char #\A を呼び insert と cursor 3 を確かめるだけで、実行結果 G02_2 は見ていない。 |
| `expected.exit_code` | 0 | `t/scenarios/G02/insert-command-cursor-shape.json:43` [残す] の "G02-insert-command-cursor-shape" expected.exit_code | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | 残す G02-insert-command-cursor-shape も NSHELL_VI_MODE=1 の実 PTY で終了コード 0 を求める。 |
| `steps[5].contains` | "G02_2" | `t/unit/test-input-state-vi.lisp:41` it "vi-i-returns-to-insert-mode" | 行エディタの reducer を直接呼ぶ (reduce-once、端末・REPL ループ・実行なし) | いいえ | 出力を待つ手順はない。 |

### G02-delete-a-word

`t/scenarios/G02/delete-a-word.json` [削除 (先にテストを足す)]

シナリオの入口: 実 PTY 上の対話 REPL (キー入力 → 行エディタ → Enter で実行 → 端末への出力)、NSHELL_VI_MODE=1 の vi モード

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "G02_A_WORD_OBJECT_OK" | `t/unit/test-input-state-vi.lisp:504` it "applies inner and around word and paired text objects" | 行エディタの reducer を直接呼ぶ (reduce-once、端末・REPL ループ・実行なし) | いいえ | buffer "one two" に d a w を reduce-once で与えてバッファを確かめるだけで、0 w w の移動も実行結果 G02_A_WORD_OBJECT_OK も見ていない。 |
| `expected.exit_code` | 0 | `t/scenarios/G02/insert-command-cursor-shape.json:43` [残す] の "G02-insert-command-cursor-shape" expected.exit_code | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | 残す G02-insert-command-cursor-shape も同じ入口で終了コード 0 を求める。 |
| `steps[2].contains` | "\u001b[2 q" | `t/scenarios/G02/insert-command-cursor-shape.json:27` [残す] の "G02-insert-command-cursor-shape" steps[2].contains | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | 残す G02-insert-command-cursor-shape も Escape の後に ESC[2 q を待つ。 |
| `steps[10].contains` | "G02_COMMAND_FINISHED" | `t/scenarios/G02/insert-command-cursor-shape.json:34` [残す] の "G02-insert-command-cursor-shape" steps[9].contains | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | 残す G02-insert-command-cursor-shape も実行後のマーカーを待つ (値は違う)。 |

### G02-delete-inner-word

`t/scenarios/G02/delete-inner-word.json` [削除 (先にテストを足す)]

シナリオの入口: 実 PTY 上の対話 REPL (キー入力 → 行エディタ → Enter で実行 → 端末への出力)、NSHELL_VI_MODE=1 の vi モード

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "G02_INNER_WORD_OBJECT_OK" | `t/unit/test-input-state-vi.lisp:504` it "applies inner and around word and paired text objects" | 行エディタの reducer を直接呼ぶ (reduce-once、端末・REPL ループ・実行なし) | いいえ | buffer "one two" に d i w を reduce-once で与えてバッファを確かめるだけで、0 w w の移動も実行結果 G02_INNER_WORD_OBJECT_OK も見ていない。 |
| `expected.exit_code` | 0 | `t/scenarios/G02/insert-command-cursor-shape.json:43` [残す] の "G02-insert-command-cursor-shape" expected.exit_code | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | 残す G02-insert-command-cursor-shape も同じ入口で終了コード 0 を求める。 |
| `steps[2].contains` | "\u001b[2 q" | `t/scenarios/G02/insert-command-cursor-shape.json:27` [残す] の "G02-insert-command-cursor-shape" steps[2].contains | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | 残す G02-insert-command-cursor-shape も Escape の後に ESC[2 q を待つ。 |
| `steps[10].contains` | "G02_COMMAND_FINISHED" | `t/scenarios/G02/insert-command-cursor-shape.json:34` [残す] の "G02-insert-command-cursor-shape" steps[9].contains | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | 残す G02-insert-command-cursor-shape も実行後のマーカーを待つ (値は違う)。 |

### G02-goto-end

`t/scenarios/G02/goto-end.json` [削除 (先にテストを足す)]

シナリオの入口: 実 PTY 上の対話 REPL (キー入力 → 行エディタ → Enter で実行 → 端末への出力)、NSHELL_VI_MODE=1 の vi モード

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "G02_GOTO_END_OK" | `t/integration/test-terminal-stream.lisp:8` it "terminal-stream-splits-vi-escape-from-buffered-keys" | read-key-event を文字列ストリームで直接呼ぶ (REPL ループ・実行なし) | いいえ | ESC G を 1 回の読み込みで渡しても 2 つのキーに分かれることだけを確かめ、G・a・f の後の実行結果 G02_GOTO_END_OK は見ていない。 |
| `expected.exit_code` | 0 | `t/scenarios/G02/insert-command-cursor-shape.json:43` [残す] の "G02-insert-command-cursor-shape" expected.exit_code | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | 残す G02-insert-command-cursor-shape も同じ入口で終了コード 0 を求める。 |
| `steps[1].contains` | "\u001b[6 q" | `t/scenarios/G02/runtime-vi-toggle.json:48` [残す] の "G02-runtime-vi-toggle" expected.stream.contains[0] | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | 残す G02-runtime-vi-toggle も ESC[6 q を stream に求める (空行の Enter 後かどうかは違う)。 |
| `steps[5].contains` | "\u001b[2 q" | `t/scenarios/G02/insert-command-cursor-shape.json:27` [残す] の "G02-insert-command-cursor-shape" steps[2].contains | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | 残す G02-insert-command-cursor-shape も Escape の後に ESC[2 q を待つ。 |
| `steps[8].contains` | "\u001b[6 q" | `t/scenarios/G02/insert-command-cursor-shape.json:29` [残す] の "G02-insert-command-cursor-shape" steps[4].contains | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | 残す G02-insert-command-cursor-shape も a の後に ESC[6 q を待つ。 |
| `steps[11].contains` | "\u001b[2 q" | `t/scenarios/G02/insert-command-cursor-shape.json:32` [残す] の "G02-insert-command-cursor-shape" steps[7].contains | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | 残す G02-insert-command-cursor-shape も 2 回目の Escape の後に ESC[2 q を待つ。 |
| `steps[13].contains` | "G02_COMMAND_FINISHED" | `t/scenarios/G02/insert-command-cursor-shape.json:34` [残す] の "G02-insert-command-cursor-shape" steps[9].contains | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | 残す G02-insert-command-cursor-shape も実行後のマーカーを待つ (値は違う)。 |

### G02-undo-find-replace-repeat

`t/scenarios/G02/undo-find-replace-repeat.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "G02_VI_ACTIONS_OK" | なし | f の検索 (`t/unit/test-input-state-vi.lisp:425`)、r の置換 (:526)、. と u (:540) は個別に確かめられているが、r を . で繰り返すことと、u で戻した後に . で繰り返すことを確かめるテストはない。 |
| `expected.exit_code` | 0 | `t/scenarios/G02/insert-command-cursor-shape.json:43` [残す] の "G02-insert-command-cursor-shape" expected.exit_code | 残す G02-insert-command-cursor-shape が NSHELL_VI_MODE=1 のセッションの終了コード 0 を assert している。 |
| `steps[2].contains` | "\u001b[2 q" | `t/scenarios/G02/insert-command-cursor-shape.json:27` [残す] の "G02-insert-command-cursor-shape" steps[2].contains | 残す G02-insert-command-cursor-shape が Escape の後の \e[2 q を assert している。 |
| `steps[17].contains` | "G02_COMMAND_FINISHED" | `t/scenarios/G02/insert-command-cursor-shape.json:34` [残す] の "G02-insert-command-cursor-shape" steps[9].contains | checker.sh が必ず出す同期の印。残す G02-insert-command-cursor-shape が vi で編集した行を Enter で実行して出力が届くことを assert している。 |

### G02-vi-e-nfd-grapheme-boundary

`t/scenarios/G02/vi-e-nfd-grapheme-boundary.json` [削除 (先にテストを足す)]

シナリオの入口: 実 PTY 上の対話 REPL (キー入力 → 行エディタ → Enter で実行 → 端末への出力)、NSHELL_VI_MODE=1 の vi モード

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "G02_NFD_OK" | `t/unit/test-input-state-vi.lisp:222` it "vi-e-and-caret-motions" | 行エディタの reducer を直接呼ぶ (reduce-once、端末・REPL ループ・実行なし) | いいえ | buffer "echo é" (NFD) に e と x を reduce-once で与えカーソルとバッファを確かめるだけで、実行結果の出力は見ていない。 |
| `expected.stream.excludes[0]` | "G02_NFD_OKe" | `t/unit/test-input-state-vi.lisp:222` it "vi-e-and-caret-motions" | 行エディタの reducer を直接呼ぶ (reduce-once、端末・REPL ループ・実行なし) | いいえ | 出力に G02_NFD_OKe が含まれないことは確かめていない。 |
| `expected.stream.excludes[1]` | "G02_NFD_OKé" | `t/unit/test-input-state-vi.lisp:222` it "vi-e-and-caret-motions" | 行エディタの reducer を直接呼ぶ (reduce-once、端末・REPL ループ・実行なし) | いいえ | 出力に G02_NFD_OKé が含まれないことは確かめていない。 |
| `expected.exit_code` | 0 | `t/scenarios/G02/insert-command-cursor-shape.json:43` [残す] の "G02-insert-command-cursor-shape" expected.exit_code | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | 残す G02-insert-command-cursor-shape も同じ入口で終了コード 0 を求める。 |
| `steps[2].contains` | "\u001b[2 q" | `t/scenarios/G02/insert-command-cursor-shape.json:27` [残す] の "G02-insert-command-cursor-shape" steps[2].contains | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | 残す G02-insert-command-cursor-shape も Escape の後に ESC[2 q を待つ。 |
| `steps[6].contains` | "G02_NFD_OK" | `t/unit/test-input-state-vi.lisp:222` it "vi-e-and-caret-motions" | 行エディタの reducer を直接呼ぶ (reduce-once、端末・REPL ループ・実行なし) | いいえ | 出力を待つ手順はない。 |

### G02-yank-put-inner-word

`t/scenarios/G02/yank-put-inner-word.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "G02_YANK_PUT_OK" | なし | `t/unit/test-input-state-vi.lisp:476` は yw のヤンク、504 は diw の削除を確かめるだけで、y と iw を組み合わせて "a" をヤンクし p で "sh checker.sh aa" にする手順を確かめるテストはない。 |
| `expected.exit_code` | 0 | `t/scenarios/G02/insert-command-cursor-shape.json:43` [残す] の G02-insert-command-cursor-shape expected.exit_code | vi モードで exit と Enter により終了コード 0 になることを、残す G02-insert-command-cursor-shape が同じ手順で確かめている。 |
| `steps[2].contains` | "\u001b[2 q" | `t/scenarios/G02/insert-command-cursor-shape.json:27` [残す] の G02-insert-command-cursor-shape steps[2].contains | vi の insert から Escape で command へ移ると \e[2 q が出ることを、残す G02 の steps[2] が同じ操作（入力後に Escape）で確かめている。 |
| `steps[8].contains` | "G02_COMMAND_FINISHED" | `t/scenarios/G02/insert-command-cursor-shape.json:34` [残す] の G02-insert-command-cursor-shape steps[9].contains | checker.sh は引数によらず G02_COMMAND_FINISHED を出す。command モードからの Enter で行が実行されることを残す G02 の steps[9] が確かめている。 |

### G03-undo-redo

`t/scenarios/G03/undo-redo.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "G03_UNDO_REDO_OK" | なし | `t/unit/test-input-state-case-undo.lisp:53` は 1 回の C-_、65 は C-_ の後の Alt-R だけを確かめる。シナリオは x を打って C-_、Alt-R、もう一度 C-_ と進め "sh checker.sh proof" に戻す。やり直しの後の取り消しを確かめるテストはない。 |
| `expected.exit_code` | 0 | `t/scenarios/I04/multiline-history-suggestion.json:87` [残す] の I04-multiline-history-suggestion expected.exit_code | exit と Enter で終了コード 0 になることを残す I04 が同じ手順で確かめている。 |
| `steps[6].contains` | "G03_UNDO_REDO_OK" | なし | expected.stream.contains[0] と同じ出力。redo の後の undo を確かめるテストはない。 |

### G04-approx-kill-ring-yank

`t/scenarios/G04/approx-kill-ring-yank.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.side_effects.files[0].path` | "discarded" | なし | `t/unit/test-input-state-kill-yank.lisp:222` と `t/unit/test-input-state-kill-yank-properties.lisp:19` は kill した直後に同じ位置へ yank するだけ。C-k の後に "touch " を打ち、その後の C-y で別の位置に "discarded" を挿入する（自己挿入で kill ring が消えない）手順を確かめるテストはない。 |
| `expected.side_effects.files[0].exists` | true | なし | files[0].path と同じ。編集後の行 "touch discarded; ..." の組み立てを確かめるテストはない。 |
| `expected.exit_code` | 0 | `t/scenarios/I04/multiline-history-suggestion.json:87` [残す] の I04-multiline-history-suggestion expected.exit_code | exit と Enter で終了コード 0 になることを残す I04 が同じ手順で確かめている。 |
| `steps[7].contains` | "G04_2" | `t/scenarios/I04/multiline-history-suggestion.json:65` [残す] の I04-multiline-history-suggestion steps[7].contains | G04_2 は行の後半 "; echo G04_$((1+1))" の出力で、yank の結果によらず出る。入力した bare-line の echo（変数・算術展開を含む）が実行され出力が届くことを、残す I04 の steps[7] が同じ形で確かめている（同期用の目印）。 |

### G04-kill-ring-yank-pop

`t/scenarios/G04/kill-ring-yank-pop.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "G04_KILL_RING_YANK_POP_OK" | なし | `t/unit/test-input-state-kill-yank.lisp:246` と `t/e2e/test-smoke-editing.lisp:192` は連続した C-w で kill ring を積み、`t/unit/test-input-state-kill-yank-properties.lisp:105` は kill ring を最初から与える。シナリオは M-b を挟んだ 2 回の M-d で "wrong" と "unused" を積み、C-y の後に M-y で "wrong" に替える。キーが違い、この手順を確かめるテストはない。 |
| `expected.exit_code` | 0 | `t/scenarios/I04/multiline-history-suggestion.json:87` [残す] の I04-multiline-history-suggestion expected.exit_code | exit と Enter で終了コード 0 になることを残す I04 が同じ手順で確かめている。 |
| `steps[8].contains` | "G04_KILL_RING_YANK_POP_OK" | なし | expected.stream.contains[0] と同じ出力。M-d による kill と M-y の組合せを確かめるテストはない。 |

### G05-approx-multiline-buffer-navigation

`t/scenarios/G05/approx-multiline-buffer-navigation.json` [削除 (先にテストを足す)]

シナリオの入口: 実 PTY 上の対話 REPL (キー入力 → 行エディタ → Enter で実行 → 端末への出力)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.side_effects.files[0].path` | "G05_FIRSTX" | `t/unit/test-input-state-continuation.lisp:84` it "e03-vertical-motion-keeps-a-preferred-visual-column-across-short-lines" | 行エディタの reducer を直接呼ぶ (reduce-once、端末・REPL ループ・実行なし) | いいえ | 3 行のバッファで reduce-once :up のカーソル位置を確かめるだけで、X を足した行を実行してファイル G05_FIRSTX ができることは見ていない。 |
| `expected.side_effects.files[0].exists` | true | `t/unit/test-input-state-continuation.lisp:164` it "e03-ctrl-e-moves-to-the-physical-line-end-and-keeps-single-line-behavior" | 行エディタの reducer を直接呼ぶ (reduce-once、端末・REPL ループ・実行なし) | いいえ | reduce-once :ctrl-e のカーソル位置だけで、ファイルの存在は見ていない。 |
| `expected.side_effects.files[1].path` | "G05_SECOND" | `t/scenarios/G07/nested-continuation-indentation-and-single-execution.json:74` [残す] の "G07-nested-continuation-indentation-and-single-execution" steps[6].contains | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | 残す G07 は同じ入口で複数行 progn が 1 回実行されることを確かめるが、G05_SECOND は作らない。 |
| `expected.side_effects.files[1].exists` | true | `t/scenarios/G07/nested-continuation-indentation-and-single-execution.json:74` [残す] の "G07-nested-continuation-indentation-and-single-execution" steps[6].contains | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | 同上。ファイル G05_SECOND の存在は確かめていない。 |
| `expected.exit_code` | 0 | `t/scenarios/I04/multiline-history-suggestion.json:87` [残す] の "I04-multiline-history-suggestion" expected.exit_code | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | 残す I04 も同じ入口で終了コード 0 を求める。 |
| `steps[22].contains` | "G05_AFTER_2" | `t/scenarios/I04/multiline-history-suggestion.json:65` [残す] の "I04-multiline-history-suggestion" steps[7].contains | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | 残す I04 も C-c の後に打ったコマンドの出力を待つ (値は違う)。 |

### G06-nested-matching-delimiters

`t/scenarios/G06/nested-matching-delimiters.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "\u001b[7m(" | なし | `t/unit/test-input-state-continuation.lisp:188` は同じ "echo $( (echo X) )" と cursor 8 で \e[7m( を assert するが、spans を test 側で計算して render-edit-buffer に直接渡している。REPL の再描画経路が spans を渡す部分（`src/presentation/repl-rendering.lisp`）は通らない。 |
| `expected.stream.contains[1]` | "\u001b[7m)" | なし | contains[0] と同じ。\e[7m) も render-edit-buffer の直接呼び出しでしか確かめていない。 |
| `expected.exit_code` | 0 | `t/scenarios/I04/multiline-history-suggestion.json:87` [残す] の I04-multiline-history-suggestion expected.exit_code | exit と Enter で終了コード 0 になることを残す I04 が同じ手順で確かめている。 |

### WP-E03-blank-continuation-keeps-shell-alive

`t/scenarios/G07/blank-continuation-line-keeps-shell-alive.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.screen.contains[0]` | "E03_SHELL_CONTINUES" | なし | 空白だけの継続行で Enter を押したあとに後続コマンドが動くことを確かめるテストはない。`t/unit/test-input-state-continuation.lisp:4` は 1 回目の Enter で継続行に入るところまで |
| `expected.screen.excludes[0]` | "nshell error" | なし | 継続行で 2 回目の Enter を押しても "nshell error" が出ないことを、出力の不在で確かめるテストはない |
| `expected.exit_code` | 0 | `t/unit/test-repl-execution.lisp:12` it "repl-installed-terminal-controls-actual-runner-lifecycle" | render-prompt-cont が +repl-exit+ を返して REPL が終わると run-repl が 0 を返すことを :success の場合で確かめる (exit 組み込みで +repl-exit+ に至ることは `t/unit/test-repl-state.lisp:255` が確かめる)。セッションを exit で終えて 0 になる流れを最後まで駆動している |

### G08-structural-editing

`t/scenarios/G08/structural-editing.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.screen.excludes[0]` | "nshell error" | なし | キー操作の途中で処理が失敗しないことを示す不在の assert だが、シナリオのキー列を通すテストがないので、どのテストもこれを確かめていない。 |
| `expected.exit_code` | 0 | `t/scenarios/I04/multiline-history-suggestion.json:87` [残す] の I04-multiline-history-suggestion expected.exit_code | exit と Enter で終了コード 0 になることを残す I04 が同じ手順で確かめている。 |
| `steps[11].contains` | "(list (list G08_CHILD ) G08_AFTER)" | なし | `t/unit/test-input-state-structural-editing.lisp:4` は 1 段のリスト "(list alpha beta)" の移動、`t/unit/test-input-state-structural-editing.lisp:34` は語の先頭からの C-M-k だけを確かめる。入れ子のリストへ C-M-d で入り、空白の前から C-M-k で "G08_TARGET" だけを消す手順を確かめるテストはない。 |
| `steps[29].contains` | "(list (list G08_CHILD G08_TARGET) G08_AFTER G08_NEW)" | なし | kill した位置の後ろへ C-f で動いてから C-y し、C-M-u、C-M-f、C-M-b を続ける手順を確かめるテストはない。 |
| `steps[43].contains` | "(+ G08_BW_LEFT G08_BW_KILL G08_BW_RIGHT G08_BW_NEW)" | なし | `t/unit/test-input-state-structural-editing.lisp:34` は C-M-Delete で "alpha" を消すが、その後の C-y は確かめていない（yank は C-M-k の後だけ）。後方削除の直後の C-y で元に戻る流れを確かめるテストはない。 |

### G09-approx-balanced-parentheses-before-enter

`t/scenarios/G09/approx-balanced-parentheses-before-enter.json` [削除 (先にテストを足す)]

シナリオの入口: 実 PTY 上の対話 REPL (キー入力 → 行エディタ → Enter で実行 → 端末への出力)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "G09_BALANCED" | `t/scenarios/G07/nested-continuation-indentation-and-single-execution.json:74` [残す] の "G07-nested-continuation-indentation-and-single-execution" steps[6].contains | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | 残す G07 は同じ入口で、閉じ括弧の Enter で継続行が 1 回実行されることを確かめるが、(echo $G09_MESSAGE …) の環境変数展開の出力 G09_BALANCED は確かめていない。 |
| `expected.exit_code` | 0 | `t/scenarios/I04/multiline-history-suggestion.json:87` [残す] の "I04-multiline-history-suggestion" expected.exit_code | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | 残す I04 も同じ入口で終了コード 0 を求める。 |
| `steps[4].contains` | "G09_BALANCED G09_SUB" | `t/scenarios/G07/nested-continuation-indentation-and-single-execution.json:74` [残す] の "G07-nested-continuation-indentation-and-single-execution" steps[6].contains | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | G07 は format と printf の出力を待つだけで、S 式の echo が 2 行にまたがった引数を出すことは確かめていない。 |
| `steps[8].contains` | "G09_READY_MARKER" | `t/scenarios/G07/nested-continuation-indentation-and-single-execution.json:87` [残す] の "G07-nested-continuation-indentation-and-single-execution" steps[9].contains | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | G07 も echo $G07_READY の出力を待つが、シナリオは直前に C-c を打つ。 |
| `steps[13].contains` | "G09_AFTER_2" | `t/scenarios/G07/nested-continuation-indentation-and-single-execution.json:74` [残す] の "G07-nested-continuation-indentation-and-single-execution" steps[6].contains | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | G07 の format t の出力待ちで、~d と (+ 1 1) の出力 G09_AFTER_2 と C-a C-k の後の実行は確かめていない。 |

### G11-clear-screen-keeps-prompt

`t/scenarios/G11/clear-screen-keeps-prompt.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "G11_BEFORE_CLEAR" | `t/e2e/test-smoke-editing.lisp:226` it "e2e-here-document-tail-command-executes" | cat の出力が execute-ast から返ることを assert している（ファイルではなくヒアドキュメントだが、外部コマンドの標準出力をそのまま出す同じ経路）。 |
| `expected.screen.excludes[0]` | "G11_BEFORE_CLEAR" | なし | `t/unit/test-repl-rendering.lisp:98` と `t/e2e/test-smoke-editing.lisp:142` は ESC[2J と ESC[1;1H が出ることだけを assert する。消去の後の再描画が前のコマンド出力を出し直さないこと（不在）はどのテストも確かめていない。 |
| `expected.exit_code` | 0 | `t/scenarios/I04/multiline-history-suggestion.json:87` [残す] の I04-multiline-history-suggestion expected.exit_code | exit と Enter で終了コード 0 になることを残す I04 が同じ手順で確かめている。 |
| `steps[2].contains` | "G11_BEFORE_CLEAR" | `t/e2e/test-smoke-editing.lisp:226` it "e2e-here-document-tail-command-executes" | contains[0] と同じ出力を待つ同期。 |
| `steps[6].contains` | "G11_2" | `t/scenarios/I04/multiline-history-suggestion.json:65` [残す] の I04-multiline-history-suggestion steps[7].contains | C-l の後も編集状態が保たれることは `t/e2e/test-smoke-editing.lisp:142` が assert している。入力した bare-line の echo（変数・算術展開を含む）が実行され出力が届くことを、残す I04 の steps[7] が同じ形で確かめている（同期用の目印）。 |

### G11-clear-screen

`t/scenarios/G11/clear-screen.json` [削除 (先にテストを足す)]

シナリオの入口: 実 PTY 上の対話 REPL (キー入力 → 行エディタ → Enter で実行 → 端末への出力)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "\u001b[2J" | `t/unit/test-repl-rendering.lisp:98` it "repl-clear-screen-clears-terminal-and-keeps-input-state" | REPL の描画関数を with-repl-test-state の中で直接呼ぶ (端末・キー入力なし) | いいえ | 画面消去の関数を直接呼び ESC[2J を出すことを確かめるだけで、PTY から 0x0c を打ってはいない。 |
| `expected.exit_code` | 0 | `t/scenarios/I04/multiline-history-suggestion.json:87` [残す] の "I04-multiline-history-suggestion" expected.exit_code | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | 残す I04 も同じ入口で終了コード 0 を求める。 |
| `steps[1].contains` | "\u001b[2J" | `t/unit/test-repl-rendering.lisp:98` it "repl-clear-screen-clears-terminal-and-keeps-input-state" | REPL の描画関数を with-repl-test-state の中で直接呼ぶ (端末・キー入力なし) | いいえ | PTY の出力を待つ手順はない。 |

### G12-approx-grapheme-cursor-boundary

`t/scenarios/G12/approx-grapheme-cursor-boundary.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "AX👩‍💻" | なし | `t/unit/test-east-asian-width.lisp:155` は右方向（move-cursor-clearing-suggestion に 1）の書記素移動だけを確かめる。C-b で ZWJ 絵文字の前へ左に 1 書記素戻る移動を確かめるテストはない。 |
| `expected.exit_code` | 0 | `t/scenarios/I04/multiline-history-suggestion.json:87` [残す] の I04-multiline-history-suggestion expected.exit_code | exit と Enter で終了コード 0 になることを残す I04 が同じ手順で確かめている。 |
| `steps[4].contains` | "AX👩‍💻" | なし | contains[0] と同じ出力。左方向の書記素移動を確かめるテストはない。 |

### G12-grapheme-boundary

`t/scenarios/G12/grapheme-boundary.json` [削除 (先にテストを足す)]

シナリオの入口: 実 PTY 上の対話 REPL (キー入力 → 行エディタ → Enter で実行 → 端末への出力)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "G12_GRAPHEME_BOUNDARY_OK" | `t/unit/test-east-asian-width.lisp:155` it "moves-and-deletes-input-by-grapheme" | backspace-before-cursor を直接呼ぶ (キー入力・REPL ループ・実行なし) | いいえ | 家族の絵文字 (シナリオの 👩‍💻 とは別) の後で backspace-before-cursor を直接呼び "ab" を確かめるだけで、C-e・Left・DEL を打って実行した結果は見ていない。 |
| `expected.exit_code` | 0 | `t/scenarios/I04/multiline-history-suggestion.json:87` [残す] の "I04-multiline-history-suggestion" expected.exit_code | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | 残す I04 も同じ入口で終了コード 0 を求める。 |
| `steps[5].contains` | "G12_GRAPHEME_BOUNDARY_OK" | `t/unit/test-east-asian-width.lisp:155` it "moves-and-deletes-input-by-grapheme" | backspace-before-cursor を直接呼ぶ (キー入力・REPL ループ・実行なし) | いいえ | 出力を待つ手順はない。 |

### G13-ctrl-y-yank

`t/scenarios/G13/ctrl-y-yank.json` [削除 (先にテストを足す)]

シナリオの入口: 実 PTY 上の対話 REPL (キー入力 → 行エディタ → Enter で実行 → 端末への出力)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "G13_CTRL_Y_YANK_OK" | `t/unit/test-input-state-kill-yank-properties.lisp:19` it "pbt-input-state-ctrl-k-then-yank-restores-buffer" | reducer に C-k と C-y を直接与える性質テスト (端末・REPL ループ・実行なし) | いいえ | 生成した行に C-k と C-y を reducer で与えてバッファが戻ることだけを確かめ、C-a と実行結果は見ていない。 |
| `expected.exit_code` | 0 | `t/scenarios/I04/multiline-history-suggestion.json:87` [残す] の "I04-multiline-history-suggestion" expected.exit_code | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | 残す I04 も同じ入口で終了コード 0 を求める。 |
| `steps[5].contains` | "G13_CTRL_Y_YANK_OK" | `t/unit/test-input-state-kill-yank-properties.lisp:19` it "pbt-input-state-ctrl-k-then-yank-restores-buffer" | reducer に C-k と C-y を直接与える性質テスト (端末・REPL ループ・実行なし) | いいえ | 出力を待つ手順はない。 |

### G13-ctrl-y-yanks-killed-text

`t/scenarios/G13/ctrl-y-yanks-killed-text.json` [削除 (先にテストを足す)]

シナリオの入口: 実 PTY 上の対話 REPL (キー入力 → 行エディタ → Enter で実行 → 端末への出力)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "G13_YANK" | `t/unit/test-input-state-kill-yank-properties.lisp:19` it "pbt-input-state-ctrl-k-then-yank-restores-buffer" | reducer に C-k と C-y を直接与える性質テスト (端末・REPL ループ・実行なし) | いいえ | C-k と C-y でバッファが戻ることだけを reducer で確かめ、$G13_MESSAGE を展開した実行結果は見ていない。 |
| `expected.exit_code` | 0 | `t/scenarios/I04/multiline-history-suggestion.json:87` [残す] の "I04-multiline-history-suggestion" expected.exit_code | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | 残す I04 も同じ入口で終了コード 0 を求める。 |
| `steps[5].contains` | "G13_YANK" | `t/unit/test-input-state-kill-yank-properties.lisp:19` it "pbt-input-state-ctrl-k-then-yank-restores-buffer" | reducer に C-k と C-y を直接与える性質テスト (端末・REPL ループ・実行なし) | いいえ | 出力を待つ手順はない。 |
| `steps[9].contains` | "G13_AFTER_2" | `t/scenarios/I04/multiline-history-suggestion.json:65` [残す] の "I04-multiline-history-suggestion" steps[7].contains | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | 残す I04 も C-c の後に打ったコマンドの出力を待つ (値は違う)。 |

### H01-history-persists-after-exit

`t/scenarios/H01/history-persists-after-exit.json` [削除 (先にテストを足す)]

シナリオの入口: 実 PTY 上の対話 REPL (キー入力 → 行エディタ → Enter で実行 → 端末への出力)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "H01_PERSISTED_ENTRY" | `t/e2e/test-history.lisp:3` it "e2e-history-persists-across-sessions" | 実 PTY 上で起動した対話 nshell (*history-file-path-override* で保存先を差し替え、--no-config) | はい | 実 PTY で printf のコマンドを打ちその出力を待つ。echo "$SCENARIO_VALUE" の展開結果 H01_PERSISTED_ENTRY は確かめていない。 |
| `expected.exit_code` | 0 | `t/scenarios/I04/multiline-history-suggestion.json:87` [残す] の "I04-multiline-history-suggestion" expected.exit_code | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | 残す I04 も同じ入口で終了コード 0 を求める。 |
| `expected.side_effects.history.path` | ".local/share/nshell/history" | `t/integration/test-file-history.lisp:448` it "file-history-xdg-path-and-empty-load" | 履歴パスを決める関数を環境変数を変えて直接呼ぶ (REPL・PTY なし) | いいえ | HOME と XDG_DATA_HOME を変えて保存先を決める関数を直接呼ぶだけで、REPL を終えた後に <HOME>/.local/share/nshell/history ができることは確かめていない。 |
| `expected.side_effects.history.contains[0]` | "echo \\\"$SCENARIO_VALUE\\\"" | `t/e2e/test-history.lisp:3` it "e2e-history-persists-across-sessions" | 実 PTY 上で起動した対話 nshell (*history-file-path-override* で保存先を差し替え、--no-config) | はい | 記録されたテキストを load-history-file で確かめるが、保存先は override で差し替えた一時ファイルで、変数を展開する前の echo \"$SCENARIO_VALUE\" が記録されることも確かめていない。 |
| `steps[2].contains` | "H01_PERSISTED_ENTRY" | `t/e2e/test-history.lisp:3` it "e2e-history-persists-across-sessions" | 実 PTY 上で起動した対話 nshell (*history-file-path-override* で保存先を差し替え、--no-config) | はい | コマンドの出力を待つ同じ同期手順 (値は違う)。 |

### H02-approx-seeded-session-history

`t/scenarios/H02/approx-seeded-session-history.json` [削除 (先にテストを足す)]

シナリオの入口: 実 PTY 上の対話 REPL (キー入力 → 行エディタ → Enter で実行 → 端末への出力)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "H02_SHARED_SEED" | `t/integration/test-file-history.lisp:378` it "file-history-seed-recalls-newest-first" | 履歴ファイルの読み込みと history-add を直接呼ぶ (REPL・PTY なし) | いいえ | 履歴ファイルを読み込んで history-add に渡す関数を直接呼ぶだけで、HOME 下の既定の履歴を読んだ REPL で C-r の検索が H02_SHARED_SEED を端末に出すことは確かめていない。 |
| `expected.exit_code` | 0 | `t/scenarios/I04/multiline-history-suggestion.json:87` [残す] の "I04-multiline-history-suggestion" expected.exit_code | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | 残す I04 も同じ入口で終了コード 0 を求める。 |
| `steps[7].contains` | "H02_AFTER_2" | `t/unit/test-input-state-search-results.lisp:143` it "input-state-history-search-ctrl-c-clears-and-exits-search-mode" | 履歴検索の reducer を直接呼ぶ (REPL ループ・実行なし) | いいえ | 検索状態に :ctrl-c を reducer で与えてバッファが空になることだけで、その後の実行結果は見ていない。 |
| `steps[10].contains` | "H02_AFTER_2" | `t/scenarios/I04/multiline-history-suggestion.json:65` [残す] の "I04-multiline-history-suggestion" steps[7].contains | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | 残す I04 も C-c の後に打ったコマンドの出力を待つ (値は違う)。 |

### H02-live-history-shared-between-sessions

`t/scenarios/H02/live-history-shared-between-sessions.json` [削除 (先にテストを足す)]

シナリオの入口: 実 PTY 上の対話 REPL (キー入力 → 行エディタ → Enter で実行 → 端末への出力)、同じ HOME で 2 セッションを順に動かす

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "H02_WRITER_DONE" | `t/scenarios/I04/multiline-history-suggestion.json:65` [残す] の "I04-multiline-history-suggestion" steps[7].contains | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | I04 は 1 セッションで、writer セッションの出力 H02_WRITER_DONE は確かめていない。 |
| `expected.stream.contains[1]` | "H02_READER_READY" | `t/scenarios/I04/multiline-history-suggestion.json:65` [残す] の "I04-multiline-history-suggestion" steps[7].contains | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | I04 は reader セッションを持たず、H02_READER_READY は確かめていない。 |
| `expected.stream.contains[2]` | "H02_READER_VALUE" | `t/unit/test-repl-history-refresh.lisp:91` it "an-external-append-is-visible-from-the-next-prompt" | 履歴の再読み込み関数を直接呼ぶ (別プロセス・PTY なし) | いいえ | 別プロセスの追記を append-history-entry で真似て再読み込み関数を直接呼ぶだけで、別の nshell が書いた記録を C-r で呼び出して実行した出力 H02_READER_VALUE は見ていない。 |
| `expected.stream.contains[3]` | "H02_READER_DONE" | `t/scenarios/I04/multiline-history-suggestion.json:65` [残す] の "I04-multiline-history-suggestion" steps[7].contains | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | I04 は H02_READER_DONE を確かめていない。 |
| `expected.exit_code` | 0 | `t/scenarios/I04/multiline-history-suggestion.json:87` [残す] の "I04-multiline-history-suggestion" expected.exit_code | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | 残す I04 も同じ入口で終了コード 0 を求める。 |
| `expected.side_effects.history.path` | ".local/share/nshell/history" | `t/integration/test-file-history.lisp:448` it "file-history-xdg-path-and-empty-load" | 履歴パスを決める関数を環境変数を変えて直接呼ぶ (REPL・PTY なし) | いいえ | 保存先を決める関数を直接呼ぶだけで、2 つのセッションが同じ既定の履歴ファイルを使うことは確かめていない。 |
| `expected.side_effects.history.contains[0]` | "SCENARIO_READER_ONLY" | `t/e2e/test-history.lisp:3` it "e2e-history-persists-across-sessions" | 実 PTY 上で起動した対話 nshell (*history-file-path-override* で保存先を差し替え、--no-config) | はい | 2 つの実プロセスで履歴が引き継がれることは確かめるが、保存先は override で、SCENARIO_READER_ONLY を含む記録は確かめていない。 |

### H03-duplicate-entry-suppression

`t/scenarios/H03/duplicate-entry-suppression.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "1" | なし | history delete が消した件数 1 を出すこと自体は `t/unit/test-builtins-core-complete.lisp:150` (delete docker ps → "1~%") が確かめるが、その履歴は history-add で直接作ったもので、REPL が同じコマンドを 2 回実行したあとに 1 件しか残らないこと (この "1" の意味) は確かめていない |
| `expected.exit_code` | 0 | `t/unit/test-repl-execution.lisp:12` it "repl-installed-terminal-controls-actual-runner-lifecycle" | render-prompt-cont が +repl-exit+ を返して REPL が終わると run-repl が 0 を返すことを :success の場合で確かめる (exit 組み込みで +repl-exit+ に至ることは `t/unit/test-repl-state.lisp:255` が確かめる)。セッションを exit で終えて 0 になる流れを最後まで駆動している |
| `steps[2].contains` | "H03_DUPLICATE" | なし | echo "$SCENARIO_VALUE" の出力を待つ同期。REPL で同じコマンドを 2 回実行する流れを確かめるテストはないので add_test で確かめる |
| `steps[5].contains` | "H03_DUPLICATE" | なし | echo "$SCENARIO_VALUE" の出力を待つ同期。REPL で同じコマンドを 2 回実行する流れを確かめるテストはないので add_test で確かめる |
| `steps[8].contains` | "1" | なし | expected.stream.contains[0] と同じ "1" を待つ。同じ理由で対応するテストはない |

### H04-leading-space-is-not-saved

`t/scenarios/H04/leading-space-is-not-saved.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "H04_PRIVATE_PREFIX" | なし | 先頭が空白のコマンドの出力を確かめるテストはない (add_test で確かめる) |
| `expected.stream.contains[1]` | "H04_SAVED_ENTRY" | なし | 2 つ目のコマンドの出力。同じく対応するテストはない |
| `expected.exit_code` | 0 | `t/unit/test-repl-execution.lisp:12` it "repl-installed-terminal-controls-actual-runner-lifecycle" | render-prompt-cont が +repl-exit+ を返して REPL が終わると run-repl が 0 を返すことを :success の場合で確かめる (exit 組み込みで +repl-exit+ に至ることは `t/unit/test-repl-state.lisp:255` が確かめる)。セッションを exit で終えて 0 になる流れを最後まで駆動している |
| `expected.side_effects.history.path` | ".local/share/nshell/history" | `t/integration/test-file-history.lisp:448` it "file-history-xdg-path-and-empty-load" | XDG_DATA_HOME が未設定・空・相対のとき history-file-path が HOME/.local/share/nshell/history を返すことを等値で確かめる |
| `expected.side_effects.history.contains[0]` | "echo \\\"$SCENARIO_SAVED_VALUE\\\"" | なし | REPL の実行が履歴ファイルにテキストを書くことを確かめるのは `t/unit/test-repl-execution.lisp:146` だが、append-history-entry をスタブにしており、ファイルの中身は見ていない |
| `expected.side_effects.history.excludes[0]` | " echo \\\"$SCENARIO_VALUE\\\"" | なし | 先頭空白で保存を飛ばす分岐 (`src/presentation/repl-output-handlers.lisp:821-822`) を試すテストはない |
| `steps[2].contains` | "H04_PRIVATE_PREFIX" | なし | 1 つ目のコマンドの出力を待つ同期。対応するテストはない |
| `steps[5].contains` | "H04_SAVED_ENTRY" | なし | 2 つ目のコマンドの出力を待つ同期。対応するテストはない |

### H05-private-mode-does-not-save-history

`t/scenarios/H05/private-mode-does-not-save-history.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "H05_EXISTING_ENTRY" | なし | `t/unit/test-repl-execution.lisp:160` は :history-p t :private-p t で履歴を読み込むことを確かめる。NSHELL_HISTORY_PRIVATE=1 は `t/unit/test-repl-execution.lisp:267` によれば history-p nil、private-p t になるが、その組合せで既存の記録を読み込むことを確かめるテストはない（`t/unit/test-repl-execution.lisp:195` は *history-loading-enabled-p* を nil にして読み込まないことを確かめている）。 |
| `expected.stream.contains[1]` | "H05_PRIVATE_ENTRY" | `t/scenarios/I04/multiline-history-suggestion.json:65` [残す] の I04-multiline-history-suggestion steps[7].contains | 入力した bare-line の echo（変数・算術展開を含む）が実行され出力が届くことを、残す I04 の steps[7] が同じ形で確かめている（同期用の目印）。 |
| `expected.screen.excludes[0]` | "echo \"$SCENARIO_PRIVATE\"" | なし | private で実行した行がメモリ上の *history* に入らないので C-r で見つからない、という不在の assert。`t/unit/test-repl-execution.lisp:195` は append-history-entry が呼ばれないことしか assert しておらず、*history* に入らないこと（`src/presentation/repl-output-handlers.lisp:820-824` で *history-persistence-enabled-p* が両方を止める）を確かめるテストはない。 |
| `expected.exit_code` | 0 | `t/scenarios/I04/multiline-history-suggestion.json:87` [残す] の I04-multiline-history-suggestion expected.exit_code | exit と Enter で終了コード 0 になることを残す I04 が同じ手順で確かめている。 |
| `expected.side_effects.history.path` | ".local/share/nshell/history" | `t/integration/test-file-history.lisp:448` it "file-history-xdg-path-and-empty-load" | HOME だけ設定し XDG_DATA_HOME を未設定・空・相対にしたとき history-file-path が $HOME/.local/share/nshell/history になることを assert している。 |
| `expected.side_effects.history.equals` | "# nshell-history-v3 111\n(:text \"echo H05_EXISTING_ENTRY\" :timestamp 1 :cwd \"/scenario/work\" :exit-code 0 :durat… | なし | `t/unit/test-repl-execution.lisp:195` は append の呼び出しが 0 回であることを stub で確かめるだけで、実ファイルの内容がバイト単位で変わらないことは確かめていない。 |
| `steps[7].contains` | "H05_PRIVATE_ENTRY" | `t/scenarios/I04/multiline-history-suggestion.json:65` [残す] の I04-multiline-history-suggestion steps[7].contains | 入力した bare-line の echo（変数・算術展開を含む）が実行され出力が届くことを、残す I04 の steps[7] が同じ形で確かめている（同期用の目印）。 |

### H06-multiline-reverse-search

`t/scenarios/H06/multiline-reverse-search.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "echo H06_NEW_START" | `t/e2e/test-history.lisp:217` it "e2e-history-reverse-search-prefers-continuation-line-prefix" | 継続行に一致する C-r が複数行の記録全体をバッファに入れることを REPL 経路で assert している。複数行の記録をファイルから読み戻すことは `t/integration/test-file-history.lisp:116` が確かめている。 |
| `expected.stream.contains[1]` | "echo H06_OLD_START" | `t/unit/test-input-state-search.lisp:322` it "input-state-history-search-selection-clamps-at-oldest-match" | 検索中にもう一度 C-r を押すと index が古い一致へ進み、apply-history-search-results-to-input-state がその記録をバッファにすることを assert している。 |
| `expected.stream.contains[2]` | "NEW_CONTINUATION" | `t/e2e/test-history.lisp:217` it "e2e-history-reverse-search-prefers-continuation-line-prefix" | contains[0] と同じ。新しい記録の継続行がバッファに入る。 |
| `expected.stream.contains[3]` | "OLD_CONTINUATION" | `t/unit/test-input-state-search.lisp:322` it "input-state-history-search-selection-clamps-at-oldest-match" | contains[1] と同じ。2 回目の C-r で古い記録の継続行がバッファに入る。 |
| `expected.stream.contains[4]` | "H06_FIRST_2" | `t/e2e/test-smoke-input.lisp:130` it "e2e-bracketed-paste-normalizes-newlines-and-undos-once" | bracketed paste が 1 つの入力としてバッファに入ることを assert している。その行の Enter による実行は残す I04 の steps[7] と同じ形。 |
| `expected.stream.contains[5]` | "H06_SECOND_4" | `t/e2e/test-smoke-input.lisp:130` it "e2e-bracketed-paste-normalizes-newlines-and-undos-once" | contains[4] と同じ。 |
| `expected.exit_code` | 0 | `t/scenarios/G02/insert-command-cursor-shape.json:43` [残す] の G02-insert-command-cursor-shape expected.exit_code | vi モードで exit と Enter により終了コード 0 になることを、残す G02-insert-command-cursor-shape が同じ手順で確かめている。 |
| `steps[2].contains` | "OLD_CONTINUATION" | なし | クエリを打った時点では新しい記録が選ばれており、古い記録の継続行は検索結果の一覧にしか出ない。`t/unit/test-repl-search-ui.lisp:213` は render-search-results を直接呼んで複数行の一覧を確かめるが、REPL の再描画（`src/presentation/repl-rendering.lisp` の render-current-history-search-panel）から一覧が出ることを確かめるテストはない。 |
| `steps[4].contains` | "OLD_CONTINUATION" | `t/unit/test-input-state-search.lisp:322` it "input-state-history-search-selection-clamps-at-oldest-match" | contains[1] と同じ。2 回目の C-r の後の同期。 |
| `steps[6].contains` | "\u001b[6 q" | `t/scenarios/G02/insert-command-cursor-shape.json:29` [残す] の G02-insert-command-cursor-shape steps[4].contains | 検索中の C-c で検索モードを抜けることは `t/unit/test-input-state-search-results.lisp:143` が assert している。insert モードの再描画で \e[6 q が出ることは、残す G02 の steps[4] が確かめている。 |
| `steps[8].contains` | "\u001b[6 q" | `t/scenarios/G02/insert-command-cursor-shape.json:29` [残す] の G02-insert-command-cursor-shape steps[4].contains | paste の後の再描画も insert モードの再描画で、残す G02 の steps[4] と同じ経路。 |
| `steps[10].contains` | "H06_FIRST_2" | `t/e2e/test-smoke-input.lisp:130` it "e2e-bracketed-paste-normalizes-newlines-and-undos-once" | contains[4] と同じ出力を待つ同期。 |
| `steps[12].contains` | "\u001b[6 q" | `t/scenarios/G02/insert-command-cursor-shape.json:29` [残す] の G02-insert-command-cursor-shape steps[4].contains | steps[8] と同じ。 |
| `steps[14].contains` | "H06_SECOND_4" | `t/e2e/test-smoke-input.lisp:130` it "e2e-bracketed-paste-normalizes-newlines-and-undos-once" | contains[5] と同じ出力を待つ同期。 |

### H07-approx-history-cwd-and-exit-filters

`t/scenarios/H07/approx-history-cwd-and-exit-filters.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "H07_TOKEN_STEP1_2" | なし | Ctrl-R 検索を Escape で抜けて C-a C-k で行を空にしたあと、打ち直したコマンドが動くことを示す。Escape の復元は `t/unit/test-input-state-search-results.lisp:4` が :ctrl-g でしか試しておらず、:escape と C-a C-k を続けた流れはないので add_test (2) で確かめる |
| `expected.stream.contains[1]` | "H07_TOKEN_STEP2_2" | なし | Ctrl-R 検索を Escape で抜けて C-a C-k で行を空にしたあと、打ち直したコマンドが動くことを示す。Escape の復元は `t/unit/test-input-state-search-results.lisp:4` が :ctrl-g でしか試しておらず、:escape と C-a C-k を続けた流れはないので add_test (2) で確かめる |
| `expected.stream.contains[2]` | "H07_TOKEN_STEP3_2" | なし | Ctrl-R 検索を Escape で抜けて C-a C-k で行を空にしたあと、打ち直したコマンドが動くことを示す。Escape の復元は `t/unit/test-input-state-search-results.lisp:4` が :ctrl-g でしか試しておらず、:escape と C-a C-k を続けた流れはないので add_test (2) で確かめる |
| `expected.exit_code` | 0 | `t/unit/test-repl-execution.lisp:12` it "repl-installed-terminal-controls-actual-runner-lifecycle" | render-prompt-cont が +repl-exit+ を返して REPL が終わると run-repl が 0 を返すことを :success の場合で確かめる (exit 組み込みで +repl-exit+ に至ることは `t/unit/test-repl-state.lisp:255` が確かめる)。セッションを exit で終えて 0 になる流れを最後まで駆動している |
| `expected.side_effects.files[0].path` | "history-cwd-status.txt" | なし | REPL で組み込みの出力を > でこのファイルに書くこと。`t/unit/test-builtins-source-pipeline.lisp:33` は source 経路の echo > file で、REPL の history ではないので add_test (1) で確かめる |
| `expected.side_effects.files[0].contains[0]` | "H07_CLI_CWD_STATUS_MATCH" | なし | history 組み込みの --cwd を試すテストはない (t/ で --cwd は 0 件)。--failed は `t/e2e/test-history.lisp:64` が、--duration-min/--duration-max/--host は `t/unit/test-search-history.lisp:157` が確かめるが、どれも --cwd と組み合わせていない |
| `expected.side_effects.files[0].excludes[0]` | "H07_CLI_CWD_STATUS_OTHER_CWD" | なし | history 組み込みの --cwd を試すテストはない (t/ で --cwd は 0 件)。--failed は `t/e2e/test-history.lisp:64` が、--duration-min/--duration-max/--host は `t/unit/test-search-history.lisp:157` が確かめるが、どれも --cwd と組み合わせていない |
| `expected.side_effects.files[0].excludes[1]` | "H07_CLI_CWD_STATUS_SUCCESS" | なし | --failed で成功した記録を落とすことは `t/e2e/test-history.lisp:64` が確かめるが、--cwd との組み合わせではない |
| `expected.side_effects.files[1].path` | "history-duration-min.txt" | なし | REPL で組み込みの出力を > でこのファイルに書くこと。`t/unit/test-builtins-source-pipeline.lisp:33` は source 経路の echo > file で、REPL の history ではないので add_test (1) で確かめる |
| `expected.side_effects.files[1].contains[0]` | "H07_CLI_DURATION_MIN_MATCH" | なし | history 組み込みの --cwd を試すテストはない (t/ で --cwd は 0 件)。--failed は `t/e2e/test-history.lisp:64` が、--duration-min/--duration-max/--host は `t/unit/test-search-history.lisp:157` が確かめるが、どれも --cwd と組み合わせていない |
| `expected.side_effects.files[1].excludes[0]` | "H07_CLI_DURATION_MIN_MISS" | なし | history 組み込みの --cwd を試すテストはない (t/ で --cwd は 0 件)。--failed は `t/e2e/test-history.lisp:64` が、--duration-min/--duration-max/--host は `t/unit/test-search-history.lisp:157` が確かめるが、どれも --cwd と組み合わせていない |
| `expected.side_effects.files[2].path` | "history-duration-max.txt" | なし | REPL で組み込みの出力を > でこのファイルに書くこと。`t/unit/test-builtins-source-pipeline.lisp:33` は source 経路の echo > file で、REPL の history ではないので add_test (1) で確かめる |
| `expected.side_effects.files[2].contains[0]` | "H07_CLI_DURATION_MAX_MATCH" | なし | history 組み込みの --cwd を試すテストはない (t/ で --cwd は 0 件)。--failed は `t/e2e/test-history.lisp:64` が、--duration-min/--duration-max/--host は `t/unit/test-search-history.lisp:157` が確かめるが、どれも --cwd と組み合わせていない |
| `expected.side_effects.files[2].excludes[0]` | "H07_CLI_DURATION_MAX_MISS" | なし | history 組み込みの --cwd を試すテストはない (t/ で --cwd は 0 件)。--failed は `t/e2e/test-history.lisp:64` が、--duration-min/--duration-max/--host は `t/unit/test-search-history.lisp:157` が確かめるが、どれも --cwd と組み合わせていない |
| `expected.side_effects.files[3].path` | "history-host.txt" | なし | REPL で組み込みの出力を > でこのファイルに書くこと。`t/unit/test-builtins-source-pipeline.lisp:33` は source 経路の echo > file で、REPL の history ではないので add_test (1) で確かめる |
| `expected.side_effects.files[3].contains[0]` | "H07_CLI_HOST_MATCH" | なし | history 組み込みの --cwd を試すテストはない (t/ で --cwd は 0 件)。--failed は `t/e2e/test-history.lisp:64` が、--duration-min/--duration-max/--host は `t/unit/test-search-history.lisp:157` が確かめるが、どれも --cwd と組み合わせていない |
| `expected.side_effects.files[3].excludes[0]` | "H07_CLI_HOST_MISS" | なし | history 組み込みの --cwd を試すテストはない (t/ で --cwd は 0 件)。--failed は `t/e2e/test-history.lisp:64` が、--duration-min/--duration-max/--host は `t/unit/test-search-history.lisp:157` が確かめるが、どれも --cwd と組み合わせていない |
| `steps[4].contains` | "H07_STEP1_2" | なし | history の CLI 実行 (ファイルへのリダイレクト) のあとに続くコマンドの出力を待つ同期。add_test (1) で続くコマンドの出力を確かめる |
| `steps[9].contains` | "H07_STEP2_2" | なし | history の CLI 実行 (ファイルへのリダイレクト) のあとに続くコマンドの出力を待つ同期。add_test (1) で続くコマンドの出力を確かめる |
| `steps[14].contains` | "H07_STEP3_2" | なし | history の CLI 実行 (ファイルへのリダイレクト) のあとに続くコマンドの出力を待つ同期。add_test (1) で続くコマンドの出力を確かめる |
| `steps[19].contains` | "H07_STEP4_2" | なし | history の CLI 実行 (ファイルへのリダイレクト) のあとに続くコマンドの出力を待つ同期。add_test (1) で続くコマンドの出力を確かめる |
| `steps[22].contains` | "履歴: duration-min:100" | なし | Ctrl-R の見出しの書式 "履歴: ~a  (~d 件)" は `t/unit/test-repl-search-ui.lisp:17` が query "git" で確かめるが、REPL で Ctrl-R を押してトークンつきの query を打ったときに見出しが描かれることは確かめていない (`t/e2e/test-history.lisp:82` は buffer だけを見る) |
| `steps[24].contains` | " (1 件)" | なし | 件数 1 件は、トークンでの絞り込み (`t/unit/test-search-history.lisp:117` は host:alpha duration-min:100 duration-max:150 の組で確かめる) と自由語の組み合わせで決まる。この組 (トークン 1 つ + 自由語) で件数を描くテストはない |
| `steps[25].contains` | "H07_TOKEN_DURATION_MIN_MATCH" | なし | トークンと自由語で絞った結果の描画。`t/unit/test-search-history.lisp:117` と :134 は use case の戻り値だけで、REPL の検索パネルの描画ではない |
| `steps[31].contains` | "H07_TOKEN_STEP1_2" | なし | Ctrl-R 検索を Escape で抜けて C-a C-k で行を空にしたあと、打ち直したコマンドが動くことを示す。Escape の復元は `t/unit/test-input-state-search-results.lisp:4` が :ctrl-g でしか試しておらず、:escape と C-a C-k を続けた流れはないので add_test (2) で確かめる |
| `steps[34].contains` | "履歴: duration-max:10" | なし | Ctrl-R の見出しの書式 "履歴: ~a  (~d 件)" は `t/unit/test-repl-search-ui.lisp:17` が query "git" で確かめるが、REPL で Ctrl-R を押してトークンつきの query を打ったときに見出しが描かれることは確かめていない (`t/e2e/test-history.lisp:82` は buffer だけを見る) |
| `steps[36].contains` | " (1 件)" | なし | 件数 1 件は、トークンでの絞り込み (`t/unit/test-search-history.lisp:117` は host:alpha duration-min:100 duration-max:150 の組で確かめる) と自由語の組み合わせで決まる。この組 (トークン 1 つ + 自由語) で件数を描くテストはない |
| `steps[37].contains` | "H07_TOKEN_DURATION_MAX_MATCH" | なし | トークンと自由語で絞った結果の描画。`t/unit/test-search-history.lisp:117` と :134 は use case の戻り値だけで、REPL の検索パネルの描画ではない |
| `steps[43].contains` | "H07_TOKEN_STEP2_2" | なし | Ctrl-R 検索を Escape で抜けて C-a C-k で行を空にしたあと、打ち直したコマンドが動くことを示す。Escape の復元は `t/unit/test-input-state-search-results.lisp:4` が :ctrl-g でしか試しておらず、:escape と C-a C-k を続けた流れはないので add_test (2) で確かめる |
| `steps[46].contains` | "履歴: host:alpha" | なし | Ctrl-R の見出しの書式 "履歴: ~a  (~d 件)" は `t/unit/test-repl-search-ui.lisp:17` が query "git" で確かめるが、REPL で Ctrl-R を押してトークンつきの query を打ったときに見出しが描かれることは確かめていない (`t/e2e/test-history.lisp:82` は buffer だけを見る) |
| `steps[48].contains` | " (1 件)" | なし | 件数 1 件は、トークンでの絞り込み (`t/unit/test-search-history.lisp:117` は host:alpha duration-min:100 duration-max:150 の組で確かめる) と自由語の組み合わせで決まる。この組 (トークン 1 つ + 自由語) で件数を描くテストはない |
| `steps[49].contains` | "H07_TOKEN_HOST_MATCH" | なし | トークンと自由語で絞った結果の描画。`t/unit/test-search-history.lisp:117` と :134 は use case の戻り値だけで、REPL の検索パネルの描画ではない |
| `steps[55].contains` | "H07_TOKEN_STEP3_2" | なし | Ctrl-R 検索を Escape で抜けて C-a C-k で行を空にしたあと、打ち直したコマンドが動くことを示す。Escape の復元は `t/unit/test-input-state-search-results.lisp:4` が :ctrl-g でしか試しておらず、:escape と C-a C-k を続けた流れはないので add_test (2) で確かめる |

### H08-delete-history-entry

`t/scenarios/H08/delete-history-entry.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "H08_CREATED_2" | なし | eval "$SCENARIO_COMMAND" の出力。REPL で eval と history delete を続けて実行するテストはないので add_test で確かめる |
| `expected.stream.contains[1]` | "H08_DELETE_FINISHED_2" | なし | history delete に続く echo の出力。対応するテストはない |
| `expected.exit_code` | 0 | `t/unit/test-repl-execution.lisp:12` it "repl-installed-terminal-controls-actual-runner-lifecycle" | render-prompt-cont が +repl-exit+ を返して REPL が終わると run-repl が 0 を返すことを :success の場合で確かめる (exit 組み込みで +repl-exit+ に至ることは `t/unit/test-repl-state.lisp:255` が確かめる)。セッションを exit で終えて 0 になる流れを最後まで駆動している |
| `expected.side_effects.history.path` | ".local/share/nshell/history" | `t/integration/test-file-history.lisp:448` it "file-history-xdg-path-and-empty-load" | XDG_DATA_HOME が未設定・空・相対のとき history-file-path が HOME/.local/share/nshell/history を返すことを等値で確かめる |
| `expected.side_effects.history.excludes[0]` | "eval \\\"$SCENARIO_COMMAND\\\"" | なし | ファイルから消えることは `t/integration/test-file-history.lisp:235` が確かめるが、*history-file-mutations-enabled-p* をテスト自身が t に束縛している。run-repl がこれを t にする束縛 (`src/presentation/repl.lisp:286-287`) と builtin から delete-history-entry までのつながりは確かめていない |
| `steps[2].contains` | "H08_CREATED_2" | なし | eval "$SCENARIO_COMMAND" の出力。REPL で eval と history delete を続けて実行するテストはないので add_test で確かめる。同期 |
| `steps[5].contains` | "H08_DELETE_FINISHED_2" | なし | history delete のあとの echo の出力を待つ同期。対応するテストはない |

### H09-up-arrow-prefix-search

`t/scenarios/H09/up-arrow-prefix-search.json` [削除 (先にテストを足す)]

シナリオの入口: 実 PTY 上の対話 REPL (キー入力 → 行エディタ → Enter で実行 → 端末への出力)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "H09_REPLAY_READBACK_2" | `t/scenarios/I04/multiline-history-suggestion.json:65` [残す] の "I04-multiline-history-suggestion" steps[7].contains | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | I04 は Up の前方一致検索をしておらず、H09_REPLAY_READBACK_2 は確かめていない。 |
| `expected.exit_code` | 0 | `t/scenarios/I04/multiline-history-suggestion.json:87` [残す] の "I04-multiline-history-suggestion" expected.exit_code | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | 残す I04 も同じ入口で終了コード 0 を求める。 |
| `expected.side_effects.files[0].path` | "prefix-results.txt" | `t/e2e/test-history.lisp:242` it "e2e-history-up-prefers-continuation-line-prefix" | 履歴を仕込んだ input-state に :up を reducer で与える (PTY・実行なし) | いいえ | 履歴を仕込んだ状態に :up を reducer で与えてバッファを確かめるだけで、呼び出した行を実行してファイルに追記することは見ていない (t/e2e にあるが PTY も実行もない)。 |
| `expected.side_effects.files[0].equals` | "H09_PREFIX_RESULT\nH09_PREFIX_RESULT\n" | `t/e2e/test-history.lisp:242` it "e2e-history-up-prefers-continuation-line-prefix" | 履歴を仕込んだ input-state に :up を reducer で与える (PTY・実行なし) | いいえ | prefix-results.txt の内容が H09_PREFIX_RESULT\nH09_PREFIX_RESULT\n に等しいことは確かめていない。 |
| `steps[2].contains` | "H09_REPLAY_READY_1" | `t/scenarios/I04/multiline-history-suggestion.json:65` [残す] の "I04-multiline-history-suggestion" steps[7].contains | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | I04 は H09_REPLAY_READY_1 を待たない。 |
| `steps[5].contains` | "H09_DECOY_2" | `t/scenarios/I04/multiline-history-suggestion.json:65` [残す] の "I04-multiline-history-suggestion" steps[7].contains | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | I04 は H09_DECOY_2 を待たない。 |
| `steps[9].contains` | "H09_REPLAY_READY_2" | `t/e2e/test-history.lisp:242` it "e2e-history-up-prefers-continuation-line-prefix" | 履歴を仕込んだ input-state に :up を reducer で与える (PTY・実行なし) | いいえ | Up で呼び出した行の実行結果 H09_REPLAY_READY_2 は見ていない。 |
| `steps[12].contains` | "H09_REPLAY_READBACK_2" | `t/scenarios/I04/multiline-history-suggestion.json:65` [残す] の "I04-multiline-history-suggestion" steps[7].contains | 残すシナリオ (実 PTY 上の対話 REPL、シナリオランナー) | はい | I04 は H09_REPLAY_READBACK_2 を待たない。 |

### H10-token-history-search

`t/scenarios/H10/token-history-search.json` [削除 (先にテストを足す)]

シナリオの入口: 実 PTY 上の対話 REPL (キー入力 → 行エディタ → C-r の履歴検索 → Enter で実行 → 端末への出力)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "before H10_TOKEN_MATCH after" | `t/unit/test-search-history.lisp:192` it "interactive-history-search-prefers-line-prefix-before-contains" | interactive-history-search-use-case を with-history で作ったメモリ上の履歴に対して直接呼ぶ（キー入力・REPL・履歴ファイルの読み込みを通らない） | いいえ | REPL の C-r が呼ぶ interactive-history-search-use-case（`src/presentation/repl-output-handlers.lisp:1029`、`src/presentation/repl-search-ui.lisp:158`）が、行頭に一致しない部分一致の "printf 'not a prefix git'" も結果に含めることを確かめている。シナリオは履歴ファイルから読んだ記録を、大文字を含む（大文字小文字を区別する）クエリで語の途中から一致させ、端末に表示させるが、そこは通らない。 |
| `expected.exit_code` | 0 | `t/scenarios/I04/multiline-history-suggestion.json:87` [残す] の I04-multiline-history-suggestion expected.exit_code | PTY 上の対話 REPL（残す I04 シナリオ） | はい | exit と Enter で終了コード 0 になることを、残す I04 が同じ入口と同じ手順で確かめている。 |
| `steps[7].contains` | "H10_AFTER_2" | なし | なし | いいえ | 検索中の Escape は `src/presentation/input-state-history-search.lisp:179` で :ctrl-g と同じ分岐だが、`t/unit/test-input-state-search-results.lisp:4` は reducer に :ctrl-g を渡すだけで、Escape で検索を抜けた後に C-a C-k と入力した行が実行されて出力が出ることを確かめるテストはない。 |

### H11-last-argument-insertion

`t/scenarios/H11/last-argument-insertion.json` [削除 (先にテストを足す)]

シナリオの入口: 対話 REPL（scripts/run-scenarios.py が nshell を PTY で起動し、キー列を端末から送る → 行エディタ → Enter で提出 → 実行 → 端末への出力）

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "H11_LAST_ARGUMENT" | `t/scenarios/F07/approx-osc-133-prompt.json:2` scenario "F07-approx-osc-133-prompt" expected.stream.contains[0] | 残す PTY シナリオ（同じ `scripts/run-scenarios.py` が nshell を PTY で起動しキーを送る） | はい | F07 が PTY で echo "$VAR"（実行時の環境変数）を入力し、その出力が端末に届くことを確かめている。値は別の目印。 |
| `expected.exit_code` | 0 | `t/scenarios/I04/multiline-history-suggestion.json:2` scenario "I04-multiline-history-suggestion" expected.exit_code | 残す PTY シナリオ（同じ `scripts/run-scenarios.py` が nshell を PTY で起動しキーを送る） | はい | I04 が PTY で exit と Enter を送り終了コード 0 を確かめている。 |
| `steps[2].contains` | "H11_LAST_ARGUMENT" | `t/scenarios/F07/approx-osc-133-prompt.json:2` scenario "F07-approx-osc-133-prompt" steps[4].contains | 残す PTY シナリオ（同じ `scripts/run-scenarios.py` が nshell を PTY で起動しキーを送る） | はい | 1 回目の echo "$VAR" の出力を待つ同期と同じ形を F07 が待っている。 |
| `steps[6].contains` | "H11_LAST_ARGUMENT" | `t/e2e/test-history.lisp:281` it "e2e-history-alt-dot-inserts-last-argument-for-editing" | reduce-input-state に :alt-dot イベントを直接渡し、記録は with-repl-history-lines で置く（端末からの ESC . の復号、Enter による提出と実行、同じセッションでの記録を通らない） | いいえ | バッファが "echo --short" になることだけを見ており、ESC . を端末から送って直前の実行の最後の引数（引用符付き "$SCENARIO_VALUE"）を挿入し、実行した出力に H11_LAST_ARGUMENT が出ることは確かめていない。 |

### H12-history-expansion

`t/scenarios/H12/history-expansion.json` [削除 (先にテストを足す)]

シナリオの入口: 対話 REPL（scripts/run-scenarios.py が nshell を PTY で起動し、キー列を端末から送る → 行エディタ → Enter で提出 → 実行 → 端末への出力）

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "H12_EXPANSION_WORD" | `t/scenarios/F07/approx-osc-133-prompt.json:2` scenario "F07-approx-osc-133-prompt" expected.stream.contains[0] | 残す PTY シナリオ（同じ `scripts/run-scenarios.py` が nshell を PTY で起動しキーを送る） | はい | F07 が PTY で echo "$VAR" の出力が端末に届くことを確かめている。値は別の目印。 |
| `expected.exit_code` | 0 | `t/scenarios/I04/multiline-history-suggestion.json:2` scenario "I04-multiline-history-suggestion" expected.exit_code | 残す PTY シナリオ（同じ `scripts/run-scenarios.py` が nshell を PTY で起動しキーを送る） | はい | I04 が PTY で exit と Enter を送り終了コード 0 を確かめている。 |
| `steps[2].contains` | "H12_EXPANSION_WORD" | `t/scenarios/F07/approx-osc-133-prompt.json:2` scenario "F07-approx-osc-133-prompt" steps[4].contains | 残す PTY シナリオ（同じ `scripts/run-scenarios.py` が nshell を PTY で起動しキーを送る） | はい | 1 回目の echo "$VAR" の出力を待つ同期と同じ形を F07 が待っている。 |
| `steps[5].contains` | "H12_EXPANSION_WORD" | `t/unit/test-history-expansion.lisp:4` it "expands-the-most-recent-command" | domain の history-expand-line を直接呼ぶ（キー入力・提出・実行を通らない） | いいえ | !! の展開結果の文字列だけを見ており、!$ を入力して実行した出力は確かめていない。 |
| `steps[8].contains` | "H12_EXPANSION_WORD" | `t/unit/test-repl-execution.lisp:146` it "repl-execute-expands-history-designator-before-parsing" | :execute 出力イベントを直接処理し、バッファは with-repl-input-state で置く（キー入力と Enter を通らず、出力ではなく保存する文字列を見る） | いいえ | !! が展開されてから保存されることを見ているが、PTY で !! と Enter を送り展開後の echo の出力が端末に出ることは確かめていない。 |

### H13-malformed-history-recovers

`t/scenarios/H13/malformed-history-recovers.json` [削除 (先にテストを足す)]

シナリオの入口: 実 PTY 上の対話 REPL (キー入力 → 行エディタ → C-r の履歴検索 → Enter で実行 → 端末への出力)

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "nshell: history: unable to read" | なし | なし | いいえ | `src/infrastructure/persistence/file-history.lisp:261` の "unable to ~a" で "read" を出すことを確かめるテストはない（`t/integration/test-file-history.lisp:580` は load を直接呼んで通知が 1 行であることを数えるだけ）。起動時の履歴読み込みから端末に出ることも確かめていない。 |
| `expected.stream.contains[1]` | "H13_BEFORE_REPLAY_RESULT" | なし | なし | いいえ | 壊れたフレームの前の記録を C-r で探し Right で確定し Enter で実行して出力が出ることを、REPL の C-r の入口で確かめるテストはない。`t/e2e/test-history.lisp:158` は Right で確定した buffer を、`t/e2e/test-history.lisp:109` は Enter が :execute を返すことを確かめるが、どちらも reducer を直接呼び、結果は REPL が使わない search-history-use-case :contains で作り、実行もしない。読み込みは `t/integration/test-file-history.lisp:303` が単独の壊れた記録だけを見る。 |
| `expected.stream.contains[2]` | "H13_AFTER_REPLAY_RESULT" | なし | なし | いいえ | contains[1] と同じ。壊れたフレームの後ろの記録を C-r で再実行する経路を通るテストはない。 |
| `expected.stream.contains[3]` | "H13_RECOVERY_OK" | `t/scenarios/I04/multiline-history-suggestion.json:65` [残す] の I04-multiline-history-suggestion steps[7].contains | PTY 上の対話 REPL（残す I04 シナリオ） | はい | 入力した bare-line の echo（変数・算術展開を含む）が実行され出力が届くことを、残す I04 の steps[7] が同じ入口で確かめている（同期用の目印）。 |
| `expected.exit_code` | 0 | `t/scenarios/I04/multiline-history-suggestion.json:87` [残す] の I04-multiline-history-suggestion expected.exit_code | PTY 上の対話 REPL（残す I04 シナリオ） | はい | exit と Enter で終了コード 0 になることを、残す I04 が同じ入口と同じ手順で確かめている。 |
| `expected.side_effects.history.path` | ".local/share/nshell/history" | `t/integration/test-file-history.lisp:448` it "file-history-xdg-path-and-empty-load" | history-file-path と load を直接呼ぶ（REPL の起動と終了を通らない） | いいえ | HOME だけ設定し XDG_DATA_HOME を未設定・空・相対にしたとき history-file-path が $HOME/.local/share/nshell/history になることを確かめている。REPL がそのパスに書くことは通らない。 |
| `expected.side_effects.history.contains[0]` | "echo \\\"$SCENARIO_BEFORE_RESULT\\\" # H13_BEFORE_CORRUPTION" | なし | なし | いいえ | 壊れたフレームを含むファイルに REPL が追記した後も前の記録がファイルに残ることを確かめるテストはない（`t/integration/test-file-history.lisp:580` は不正なバイトの場合だけ）。 |
| `expected.side_effects.history.contains[1]` | "echo \\\"$SCENARIO_AFTER_RESULT\\\" # H13_AFTER_CORRUPTION" | なし | なし | いいえ | contains[0] と同じ。後ろの記録が残ることは確かめていない。 |
| `expected.side_effects.history.contains[2]` | "echo \\\"$SCENARIO_VALUE\\\"" | なし | なし | いいえ | 壊れたフレームを含むファイルへ、REPL で入力した行が追記されることは確かめていない。 |
| `steps[10].contains` | "H13_RECOVERY_OK" | `t/scenarios/I04/multiline-history-suggestion.json:65` [残す] の I04-multiline-history-suggestion steps[7].contains | PTY 上の対話 REPL（残す I04 シナリオ） | はい | 入力した bare-line の echo が実行され出力が届くことを、残す I04 の steps[7] が同じ入口で確かめている（同期用の目印）。 |

### H14-approx-history-timestamp-metadata

`t/scenarios/H14/approx-history-timestamp-metadata.json` [削除 (先にテストを足す)]

シナリオの入口: 対話 REPL（scripts/run-scenarios.py が nshell を PTY で起動し、キー列を端末から送る → 行エディタ → Enter で提出 → 実行 → 端末への出力）

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "H14_TIMESTAMP_ENTRY" | `t/e2e/test-history.lisp:3` it "e2e-history-persists-across-sessions" | 実 PTY で nshell の MAIN を起動（%e2e-pty-spawn）するが、*history-file-path-override* で履歴ファイルの場所を一時ファイルに差し替える | はい | 実 PTY で入力した printf の出力が端末に届くことを確かめている。入力は echo "$VAR" ではない。 |
| `expected.exit_code` | 0 | `t/scenarios/I04/multiline-history-suggestion.json:2` scenario "I04-multiline-history-suggestion" expected.exit_code | 残す PTY シナリオ（同じ `scripts/run-scenarios.py` が nshell を PTY で起動しキーを送る） | はい | I04 が PTY で exit と Enter を送り終了コード 0 を確かめている。 |
| `expected.side_effects.history.path` | ".local/share/nshell/history" | `t/integration/test-file-history.lisp:448` it "file-history-xdg-path-and-empty-load" | history-file-path と load-history-file を関数として直接呼ぶ（REPL を起動せず、実行した行の書き込みも通らない） | いいえ | XDG_DATA_HOME を設定した場合のパスを等値で見ているが、XDG_DATA_HOME が無いときに対話で実行した行が HOME/.local/share/nshell/history に書かれることは確かめていない。 |
| `expected.side_effects.history.contains[0]` | "echo \\\"$SCENARIO_VALUE\\\"" | `t/e2e/test-history.lisp:3` it "e2e-history-persists-across-sessions" | 実 PTY で nshell の MAIN を起動（%e2e-pty-spawn）するが、*history-file-path-override* で履歴ファイルの場所を一時ファイルに差し替える | いいえ | 保存される文字列は見ているが、保存先を差し替えているうえ load-history-file で読み戻した text を比べており、既定の場所のファイルに引用符を \" と書いた `echo \"$SCENARIO_VALUE\"` が入ることは確かめていない。 |
| `steps[2].contains` | "H14_TIMESTAMP_ENTRY" | `t/e2e/test-history.lisp:3` it "e2e-history-persists-across-sessions" | 実 PTY で nshell の MAIN を起動（%e2e-pty-spawn）するが、*history-file-path-override* で履歴ファイルの場所を一時ファイルに差し替える | はい | 実 PTY で入力した行の出力を待つ同期は同じ形で行っている。値は別の目印。 |

### H14-history-persists-timestamp-metadata

`t/scenarios/H14/history-persists-timestamp-metadata.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "H14_TIMESTAMP_ENTRY" | なし | echo "$SCENARIO_VALUE" の出力。add_test で確かめる |
| `expected.exit_code` | 0 | `t/unit/test-repl-execution.lisp:12` it "repl-installed-terminal-controls-actual-runner-lifecycle" | render-prompt-cont が +repl-exit+ を返して REPL が終わると run-repl が 0 を返すことを :success の場合で確かめる (exit 組み込みで +repl-exit+ に至ることは `t/unit/test-repl-state.lisp:255` が確かめる)。セッションを exit で終えて 0 になる流れを最後まで駆動している |
| `expected.side_effects.history.path` | ".local/share/nshell/history" | `t/integration/test-file-history.lisp:448` it "file-history-xdg-path-and-empty-load" | XDG_DATA_HOME が未設定・空・相対のとき history-file-path が HOME/.local/share/nshell/history を返すことを等値で確かめる |
| `expected.side_effects.history.contains[0]` | "# nshell-history-v3" | `t/integration/test-file-history.lisp:168` it "file-history-v3-round-trip-preserves-metadata" | append-history-entry で書いたファイルの 1 行目が +history-record-v3-prefix+ で始まることを確かめる。REPL も同じ append-history-entry で書く (`src/presentation/repl-output-handlers.lisp:834-835`) |
| `expected.side_effects.history.contains[1]` | ":TIMESTAMP " | なし | v3 フレームの書き込みは `t/integration/test-file-history.lisp:168` が値を明示的に渡して確かめるが、REPL が実行時に集めた値 (`src/presentation/repl-output-handlers.lisp:748-751`、824-831) でファイルに書かれた文字列は誰も見ていない |
| `expected.side_effects.history.contains[2]` | ":CWD" | なし | v3 フレームの書き込みは `t/integration/test-file-history.lisp:168` が値を明示的に渡して確かめるが、REPL が実行時に集めた値 (`src/presentation/repl-output-handlers.lisp:748-751`、824-831) でファイルに書かれた文字列は誰も見ていない |
| `expected.side_effects.history.contains[3]` | ":EXIT-CODE" | なし | v3 フレームの書き込みは `t/integration/test-file-history.lisp:168` が値を明示的に渡して確かめるが、REPL が実行時に集めた値 (`src/presentation/repl-output-handlers.lisp:748-751`、824-831) でファイルに書かれた文字列は誰も見ていない |
| `expected.side_effects.history.contains[4]` | ":DURATION-MS " | なし | v3 フレームの書き込みは `t/integration/test-file-history.lisp:168` が値を明示的に渡して確かめるが、REPL が実行時に集めた値 (`src/presentation/repl-output-handlers.lisp:748-751`、824-831) でファイルに書かれた文字列は誰も見ていない |
| `expected.side_effects.history.contains[5]` | ":ORIGIN :TYPED" | なし | REPL で打ったコマンドの origin が :typed になること (%current-execution-origin) をファイルで確かめるテストはない。168 行は :agent を明示的に渡す |
| `expected.side_effects.history.contains[6]` | "echo \\\"$SCENARIO_VALUE\\\"" | なし | 引用符を含むコマンドがファイル上で \" と書かれること。168 行は引用符を含まない複数行のコマンドで、REPL 経由でもない |
| `expected.side_effects.history.excludes[0]` | ":TIMESTAMP NIL" | なし | REPL が集めた値が NIL にならないことを、ファイルの文字列で確かめるテストはない。`t/unit/test-repl-execution.lisp:444` はメモリ上の exit-code だけで、append-history-entry をスタブにしている |
| `expected.side_effects.history.excludes[1]` | ":CWD NIL" | なし | REPL が集めた値が NIL にならないことを、ファイルの文字列で確かめるテストはない。`t/unit/test-repl-execution.lisp:444` はメモリ上の exit-code だけで、append-history-entry をスタブにしている |
| `expected.side_effects.history.excludes[2]` | ":EXIT-CODE NIL" | なし | REPL が集めた値が NIL にならないことを、ファイルの文字列で確かめるテストはない。`t/unit/test-repl-execution.lisp:444` はメモリ上の exit-code だけで、append-history-entry をスタブにしている |
| `expected.side_effects.history.excludes[3]` | ":DURATION-MS NIL" | なし | REPL が集めた値が NIL にならないことを、ファイルの文字列で確かめるテストはない。`t/unit/test-repl-execution.lisp:444` はメモリ上の exit-code だけで、append-history-entry をスタブにしている |
| `steps[2].contains` | "H14_TIMESTAMP_ENTRY" | なし | コマンドの出力を待つ同期。add_test で確かめる |

### H14-history-timestamps-display-utc

`t/scenarios/H14/history-timestamps-display-utc.json` [削除 (先にテストを足す)]

シナリオの入口: 対話 REPL（scripts/run-scenarios.py が nshell を PTY で起動し、キー列を端末から送る → 行エディタ → Enter で提出 → 実行 → 端末への出力）

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "H14_FRESH_TIMESTAMP_OUTPUT_2" | `t/unit/test-builtins-test.lisp:162` it "evaluates complete, empty, and malformed command lines" | eval builtin を call-builtin で直接呼び、echo の実行を with-stubbed-command-executor で差し替える | いいえ | eval が引数を実行することだけを見ており、PTY から eval "$SCENARIO_COMMAND" を入力して算術展開を含む echo の出力が出ることは確かめていない。 |
| `expected.stream.contains[1]` | "H14_AFTER_TIMESTAMP_LIST_2" | `t/scenarios/I04/multiline-history-suggestion.json:2` scenario "I04-multiline-history-suggestion" steps[7].contains | 残す PTY シナリオ（同じ `scripts/run-scenarios.py` が nshell を PTY で起動しキーを送る） | はい | I04 が PTY で echo I04_AFTER_$((1+1)) を入力し、算術展開した I04_AFTER_2 が出ることを確かめている。値は別の目印。 |
| `expected.stream.contains[2]` | "1900-01-01T00:00:01Z" | `t/unit/test-search-history.lisp:157` it "history-builtin-filters-metadata-and-renders-utc-timestamps" | history builtin を call-builtin で直接呼び、記録は add-history-record でメモリに置く（起動時の履歴ファイルの読み込みと PTY を通らない） | いいえ | UTC 表示の形式は見ているが、起動時に読み込んだ :timestamp 1 の記録が 1900-01-01T00:00:01Z と表示されることは確かめていない。 |
| `expected.stream.contains[3]` | "H14_TIMESTAMP_SEEDED_RECORD" | `t/unit/test-search-history.lisp:157` it "history-builtin-filters-metadata-and-renders-utc-timestamps" | history builtin を call-builtin で直接呼ぶ（履歴ファイルの読み込みを通らない） | いいえ | メモリに置いた記録の一覧だけを見ており、ファイルから読み込んだ H14_TIMESTAMP_SEEDED_RECORD が一覧に出ることは確かめていない。 |
| `expected.exit_code` | 0 | `t/scenarios/I04/multiline-history-suggestion.json:2` scenario "I04-multiline-history-suggestion" expected.exit_code | 残す PTY シナリオ（同じ `scripts/run-scenarios.py` が nshell を PTY で起動しキーを送る） | はい | I04 が PTY で exit と Enter を送り終了コード 0 を確かめている。 |
| `steps[2].contains` | "H14_FRESH_TIMESTAMP_OUTPUT_2" | `t/unit/test-builtins-test.lisp:162` it "evaluates complete, empty, and malformed command lines" | eval builtin を call-builtin で直接呼ぶ（PTY・提出を通らない） | いいえ | contains[0] と同じで、PTY での eval の出力を待つ同期は確かめていない。 |
| `steps[7].contains` | "H14_AFTER_TIMESTAMP_LIST_2" | `t/scenarios/I04/multiline-history-suggestion.json:2` scenario "I04-multiline-history-suggestion" steps[7].contains | 残す PTY シナリオ（同じ `scripts/run-scenarios.py` が nshell を PTY で起動しキーを送る） | はい | I04 が PTY で算術展開を含む echo の出力を待つ同期を同じ形で行っている。 |

### H15-history-ignores-xdg-state-home

`t/scenarios/H15/history-ignores-xdg-state-home.json` [削除 (先にテストを足す)]

シナリオの入口: 対話 REPL（scripts/run-scenarios.py が nshell を PTY で起動し、キー列を端末から送る → 行エディタ → Enter で提出 → 実行 → 端末への出力）。cwd は HOME

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "H15_XDG_HISTORY" | `t/scenarios/F07/approx-osc-133-prompt.json:2` scenario "F07-approx-osc-133-prompt" expected.stream.contains[0] | 残す PTY シナリオ（同じ `scripts/run-scenarios.py` が nshell を PTY で起動しキーを送る） | はい | F07 が PTY で echo "$VAR" の出力が端末に届くことを確かめている。値は別の目印。 |
| `expected.exit_code` | 0 | `t/scenarios/I04/multiline-history-suggestion.json:2` scenario "I04-multiline-history-suggestion" expected.exit_code | 残す PTY シナリオ（同じ `scripts/run-scenarios.py` が nshell を PTY で起動しキーを送る） | はい | I04 が PTY で exit と Enter を送り終了コード 0 を確かめている。 |
| `expected.side_effects.files[0].path` | ".local/state/nshell/history" | `t/integration/test-file-history.lisp:448` it "file-history-xdg-path-and-empty-load" | history-file-path を関数として直接呼ぶ（REPL を起動せず、ファイルの書き込みも通らない） | いいえ | パスの選び方を等値で見ているだけで、対話の実行の後に HOME/.local/state/nshell/history が作られないことは確かめていない。 |
| `expected.side_effects.files[0].exists` | false | `t/integration/test-file-history.lisp:448` it "file-history-xdg-path-and-empty-load" | history-file-path を関数として直接呼ぶ | いいえ | 同上。state 側にファイルが無いことを実行の後に確かめていない。 |
| `expected.side_effects.history.path` | ".local/share/nshell/history" | `t/integration/test-file-history.lisp:448` it "file-history-xdg-path-and-empty-load" | history-file-path を関数として直接呼ぶ（XDG_DATA_HOME を設定した場合） | いいえ | XDG_DATA_HOME が無いとき、対話で実行した行が HOME/.local/share/nshell/history に書かれることは確かめていない。 |
| `expected.side_effects.history.contains[0]` | "echo \\\"$SCENARIO_VALUE\\\"" | `t/e2e/test-history.lisp:3` it "e2e-history-persists-across-sessions" | 実 PTY で nshell の MAIN を起動（%e2e-pty-spawn）するが、*history-file-path-override* で履歴ファイルの場所を一時ファイルに差し替える | いいえ | 保存先を差し替え、読み戻した text を比べており、既定の場所のファイルに `echo \"$SCENARIO_VALUE\"` が書かれることは確かめていない。 |
| `steps[2].contains` | "H15_XDG_HISTORY" | `t/scenarios/F07/approx-osc-133-prompt.json:2` scenario "F07-approx-osc-133-prompt" steps[4].contains | 残す PTY シナリオ（同じ `scripts/run-scenarios.py` が nshell を PTY で起動しキーを送る） | はい | echo "$VAR" の出力を待つ同期と同じ形を F07 が待っている。 |

### H15-history-uses-xdg-data-home

`t/scenarios/H15/history-uses-xdg-data-home.json` [削除 (先にテストを足す)]

シナリオの入口: 対話 REPL（scripts/run-scenarios.py が nshell を PTY で起動し、キー列を端末から送る → 行エディタ → Enter で提出 → 実行 → 端末への出力）

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "H15_XDG_HISTORY" | `t/scenarios/F07/approx-osc-133-prompt.json:2` scenario "F07-approx-osc-133-prompt" expected.stream.contains[0] | 残す PTY シナリオ（同じ `scripts/run-scenarios.py` が nshell を PTY で起動しキーを送る） | はい | F07 が PTY で echo "$VAR" の出力が端末に届くことを確かめている。値は別の目印。 |
| `expected.exit_code` | 0 | `t/scenarios/I04/multiline-history-suggestion.json:2` scenario "I04-multiline-history-suggestion" expected.exit_code | 残す PTY シナリオ（同じ `scripts/run-scenarios.py` が nshell を PTY で起動しキーを送る） | はい | I04 が PTY で exit と Enter を送り終了コード 0 を確かめている。 |
| `expected.side_effects.history.path` | ".local/share/nshell/history" | `t/integration/test-file-history.lisp:448` it "file-history-xdg-path-and-empty-load" | history-file-path を関数として直接呼ぶ（XDG_DATA_HOME を設定した場合） | いいえ | XDG_DATA_HOME が無いとき、対話で実行した行が HOME/.local/share/nshell/history に書かれることは確かめていない。 |
| `expected.side_effects.history.contains[0]` | "echo \\\"$SCENARIO_VALUE\\\"" | `t/e2e/test-history.lisp:3` it "e2e-history-persists-across-sessions" | 実 PTY で nshell の MAIN を起動（%e2e-pty-spawn）するが、*history-file-path-override* で履歴ファイルの場所を一時ファイルに差し替える | いいえ | 保存先を差し替え、読み戻した text を比べており、既定の場所のファイルに `echo \"$SCENARIO_VALUE\"` が書かれることは確かめていない。 |
| `steps[2].contains` | "H15_XDG_HISTORY" | `t/scenarios/F07/approx-osc-133-prompt.json:2` scenario "F07-approx-osc-133-prompt" steps[4].contains | 残す PTY シナリオ（同じ `scripts/run-scenarios.py` が nshell を PTY で起動しキーを送る） | はい | echo "$VAR" の出力を待つ同期と同じ形を F07 が待っている。 |

### I01-history-autosuggestion

`t/scenarios/I01/history-autosuggestion.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "I01_HISTORY_SUGGESTION" | なし | 113 は提案が input-state に付くことだけを、test-repl-rendering.lisp:301 は与えた提案の描画だけを確かめる。履歴の提案が描画されるまでを 1 本で通すテストはない |
| `expected.exit_code` | 0 | なし | 主動作に対応するテストがないので、追加テストが最後まで通ることで代わりに確かめる |
| `steps[4].contains` | "I01_AFTER_2" | `t/unit/test-input-state-search-results.lisp:124` it "input-state-ctrl-c-clears-buffer" | (同期) 提案付きの buffer で Ctrl-C を reduce し、buffer "" と suggestion nil、:redraw を確かめている。次のコマンドが実行できる状態に戻ることに当たる |

### I02-completion-autosuggestion

`t/scenarios/I02/completion-autosuggestion.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "--blue" | なし | test-autosuggest.lisp:24 は kb-add-command :flags の規則から "git st"→"atus" を出すだけで、complete -c -a で登録した引数と echo には当たらない。Alt-Right から実行までを通すテストもない |
| `expected.exit_code` | 0 | なし | 主動作に対応するテストがないので、追加テストが最後まで通ることで代わりに確かめる |
| `steps[3].contains` | "--blue" | なし | 実行結果の --blue を待つ手順で、expected.stream.contains[0] と同じ理由で対応するテストがない |

### I03-partial-word-suggestion-acceptance

`t/scenarios/I03/partial-word-suggestion-acceptance.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.exit_code` | 0 | なし | 主動作に対応するテストがないので、追加テストで確かめる |
| `expected.side_effects.files[0].path` | "I03_ALPHA" | なし | I03_ALPHA は手順 0 の touch でも作られるので、受け入れた後の実行を確かめるテストにはならない。受け入れの途中で止まることを確かめる追加テストで代える |
| `expected.side_effects.files[0].exists` | true | なし | files[0].path と同じ |
| `expected.side_effects.files[1].path` | "I03_BETA" | なし | SCENARIO_BETA を参照する手順がないので、この assertion は何も確かめていない。追加テストで提案の残りが実行されないことを確かめる |
| `expected.side_effects.files[1].exists` | false | なし | files[1].path と同じ |
| `expected.stream.contains[0]` | "I03_2" | なし | 前準備のコマンドが出す目印。主動作に対応するテストがないので追加テストで代える |
| `expected.stream.contains[1]` | "I03_3" | なし | 受け入れの後に打つコマンドが出す目印。主動作に対応するテストがないので追加テストで代える |
| `steps[2].contains` | "I03_2" | なし | 前準備の目印を待つ同期。contains[0] と同じ |
| `steps[8].contains` | "I03_3" | なし | 後続コマンドの目印を待つ同期。contains[1] と同じ |

### I05-cwd-ranked-history-suggestion

`t/scenarios/I05/cwd-ranked-history-suggestion.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.side_effects.files[0].path` | "a/I05_A_FILE" | なし | test-autosuggest.lisp:264 は compute-suggestion に :directory を直接渡し、手で作った record を使う。REPL が実行時に cwd を記録し、提案時に cwd を渡す経路は通らない |
| `expected.side_effects.files[0].exists` | true | なし | files[0].path と同じ |
| `expected.side_effects.files[1].path` | "b/I05_B_FILE" | なし | files[0].path と同じ。別ディレクトリの新しい記録が選ばれないことを REPL 経由で確かめるテストがない |
| `expected.side_effects.files[1].exists` | false | なし | files[1].path と同じ |
| `expected.side_effects.files[2].path` | "a/I05_" | なし | Alt-Right が "A_FILE" までを受け入れ、途中の "touch I05_" を実行しないことを、この提案で確かめるテストがない |
| `expected.side_effects.files[2].exists` | false | なし | files[2].path と同じ |
| `expected.exit_code` | 0 | なし | 主動作に対応するテストがないので、追加テストが最後まで通ることで代わりに確かめる |
| `steps[1].contains` | "mkdir -p a b" | なし | 入力のエコーか前準備の目印を待つ同期。主動作 (cwd ごとの履歴の記録と順位付けを REPL で通すこと) に対応するテストがないので、追加テストで代える |
| `steps[3].contains` | "I05_SETUP_2" | なし | 入力のエコーか前準備の目印を待つ同期。主動作 (cwd ごとの履歴の記録と順位付けを REPL で通すこと) に対応するテストがないので、追加テストで代える |
| `steps[5].contains` | "cd a; echo I05_SETUP_" | なし | 入力のエコーか前準備の目印を待つ同期。主動作 (cwd ごとの履歴の記録と順位付けを REPL で通すこと) に対応するテストがないので、追加テストで代える |
| `steps[7].contains` | "I05_SETUP_3" | なし | 入力のエコーか前準備の目印を待つ同期。主動作 (cwd ごとの履歴の記録と順位付けを REPL で通すこと) に対応するテストがないので、追加テストで代える |
| `steps[9].contains` | "touch I05_A_FILE" | なし | 入力のエコーか前準備の目印を待つ同期。主動作 (cwd ごとの履歴の記録と順位付けを REPL で通すこと) に対応するテストがないので、追加テストで代える |
| `steps[11].contains` | "I05_SETUP_4" | なし | 入力のエコーか前準備の目印を待つ同期。主動作 (cwd ごとの履歴の記録と順位付けを REPL で通すこと) に対応するテストがないので、追加テストで代える |
| `steps[13].contains` | "rm I05_A_FILE" | なし | 入力のエコーか前準備の目印を待つ同期。主動作 (cwd ごとの履歴の記録と順位付けを REPL で通すこと) に対応するテストがないので、追加テストで代える |
| `steps[15].contains` | "I05_SETUP_5" | なし | 入力のエコーか前準備の目印を待つ同期。主動作 (cwd ごとの履歴の記録と順位付けを REPL で通すこと) に対応するテストがないので、追加テストで代える |
| `steps[17].contains` | "cd ../b; echo I05_SETUP_" | なし | 入力のエコーか前準備の目印を待つ同期。主動作 (cwd ごとの履歴の記録と順位付けを REPL で通すこと) に対応するテストがないので、追加テストで代える |
| `steps[19].contains` | "I05_SETUP_6" | なし | 入力のエコーか前準備の目印を待つ同期。主動作 (cwd ごとの履歴の記録と順位付けを REPL で通すこと) に対応するテストがないので、追加テストで代える |
| `steps[21].contains` | "touch I05_B_FILE" | なし | 入力のエコーか前準備の目印を待つ同期。主動作 (cwd ごとの履歴の記録と順位付けを REPL で通すこと) に対応するテストがないので、追加テストで代える |
| `steps[23].contains` | "I05_SETUP_7" | なし | 入力のエコーか前準備の目印を待つ同期。主動作 (cwd ごとの履歴の記録と順位付けを REPL で通すこと) に対応するテストがないので、追加テストで代える |
| `steps[25].contains` | "rm I05_B_FILE" | なし | 入力のエコーか前準備の目印を待つ同期。主動作 (cwd ごとの履歴の記録と順位付けを REPL で通すこと) に対応するテストがないので、追加テストで代える |
| `steps[27].contains` | "I05_SETUP_8" | なし | 入力のエコーか前準備の目印を待つ同期。主動作 (cwd ごとの履歴の記録と順位付けを REPL で通すこと) に対応するテストがないので、追加テストで代える |
| `steps[29].contains` | "cd ../a; echo I05_SETUP_" | なし | 入力のエコーか前準備の目印を待つ同期。主動作 (cwd ごとの履歴の記録と順位付けを REPL で通すこと) に対応するテストがないので、追加テストで代える |
| `steps[31].contains` | "I05_SETUP_9" | なし | 入力のエコーか前準備の目印を待つ同期。主動作 (cwd ごとの履歴の記録と順位付けを REPL で通すこと) に対応するテストがないので、追加テストで代える |
| `steps[36].contains` | "echo I05_AFTER_" | なし | 入力のエコーか前準備の目印を待つ同期。主動作 (cwd ごとの履歴の記録と順位付けを REPL で通すこと) に対応するテストがないので、追加テストで代える |
| `steps[38].contains` | "I05_AFTER_2" | なし | 入力のエコーか前準備の目印を待つ同期。主動作 (cwd ごとの履歴の記録と順位付けを REPL で通すこと) に対応するテストがないので、追加テストで代える |
| `steps[40].contains` | "exit" | なし | 入力のエコーか前準備の目印を待つ同期。主動作 (cwd ごとの履歴の記録と順位付けを REPL で通すこと) に対応するテストがないので、追加テストで代える |

### I06-enter-does-not-accept-suggestion

`t/scenarios/I06/enter-does-not-accept-suggestion.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.exit_code` | 0 | `t/unit/test-input-state-commands.lisp:172` it "input-state-enter-does-not-accept-suggestion-at-eol" | (同期) 提案付きの状態で Enter を reduce し、:execute と入力済みの buffer だけが残ることを確かめている。主動作を最後まで通している |
| `expected.side_effects.files[0].path` | "I06_SUGGESTION_WOULD_RUN" | `t/unit/test-input-state-commands.lisp:172` it "input-state-enter-does-not-accept-suggestion-at-eol" | Enter の結果が :execute で buffer "echo"、suggestion nil。提案の文字列は実行対象に入らないので、提案の実行で作られるファイルがないことに当たる |
| `expected.side_effects.files[0].exists` | false | `t/unit/test-input-state-commands.lisp:172` it "input-state-enter-does-not-accept-suggestion-at-eol" | files[0].path と同じ |
| `steps[2].contains` | "I06_2" | `t/unit/test-input-state-commands.lisp:172` it "input-state-enter-does-not-accept-suggestion-at-eol" | (同期) 前準備の S 式が出す目印を待つ手順。主動作は 172 が最後まで通している |
| `steps[5].contains` | "I06_MARKER_2" | `t/unit/test-input-state-commands.lisp:172` it "input-state-enter-does-not-accept-suggestion-at-eol" | (同期) 前準備の S 式が出す目印を待つ手順。主動作は 172 が最後まで通している |
| `steps[11].contains` | "I06_AFTER_2" | なし | "touc" は 127 で終わり、command-not-found の fallback が残る (`src/presentation/repl-output-handlers.lisp:800-810`)。そこで Ctrl-C を押して次のコマンドが動くことを確かめるテストはない。`t/unit/test-repl-ask.lisp:615` は Ctrl-C ではなく文字キーを使う |

### I06-enter-typed-text-only

`t/scenarios/I06/enter-typed-text-only.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "I06_TYPED_COMMAND_PROOF" | `t/unit/test-input-state-commands.lisp:172` it "input-state-enter-does-not-accept-suggestion-at-eol" | Enter の結果が :execute で、入力済みの buffer "echo" だけが実行対象になる。打った "sh checker.sh s" が実行されることに当たる |
| `expected.stream.excludes[0]` | "I06_SUGGESTION_EXECUTED" | `t/unit/test-input-state-commands.lisp:172` it "input-state-enter-does-not-accept-suggestion-at-eol" | Enter 後の suggestion が nil で buffer が "echo" に等しい。提案 "uggested" を含む行が実行されないことを等式で確かめている |
| `expected.exit_code` | 0 | `t/unit/test-input-state-commands.lisp:172` it "input-state-enter-does-not-accept-suggestion-at-eol" | (同期) 主動作の Enter を最後まで通し、:execute を確かめている |
| `steps[1].contains` | "uggested" | なし | 旧形式 ~/.nshell_history の履歴から "uggested" の提案が描画されるまでを通すテストはない。test-repl-suggestion-worker.lisp:113 は描画を見ず、test-repl-rendering.lisp:301 は与えた提案を描くだけ |
| `steps[3].contains` | "I06_COMMAND_FINISHED" | `t/unit/test-input-state-commands.lisp:172` it "input-state-enter-does-not-accept-suggestion-at-eol" | (同期) checker.sh が出す目印を待つ手順。主動作は 172 が最後まで通している |

### I06-paste-enter-typed-text-only

`t/scenarios/I06/paste-enter-typed-text-only.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "I06_PASTE_TYPED_PROOF" | なし | test-input-state-insertion.lisp:438 は貼り付けの挿入だけを、test-input-state-commands.lisp:172 は打鍵で作った状態の Enter だけを確かめる。貼り付けの後に提案が付き、Enter で貼り付けた文字列だけを実行することを通すテストがない |
| `expected.stream.excludes[0]` | "I06_PASTE_SUGGESTION_EXECUTED" | なし | contains[0] と同じ。貼り付け後の Enter で提案が捨てられることを確かめるテストがない |
| `expected.exit_code` | 0 | なし | 主動作に対応するテストがないので、追加テストが最後まで通ることで代わりに確かめる |
| `steps[1].contains` | "uggested" | なし | 貼り付けた直後に履歴の提案 "uggested" が描画されることを確かめるテストがない |
| `steps[3].contains` | "I06_PASTE_COMMAND_FINISHED" | なし | checker.sh の目印を待つ同期。主動作に対応するテストがないので追加テストで代える |

### I07-suggestion-keystrokes-remain-responsive

`t/scenarios/I07/suggestion-keystrokes-remain-responsive.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "I07_HISTORY_SUGGESTION" | なし | v3 履歴から I07_HISTORY の提案が描画されるまでを通すテストはない。test-repl-suggestion-worker.lisp:48 と :21 は別スレッドでの計算と入力の優先を確かめるが、描画は見ない |
| `expected.screen.contains[0]` | "I07_AFTER_2" | `t/unit/test-input-state-search-results.lisp:124` it "input-state-ctrl-c-clears-buffer" | (同期) 提案付きの buffer で Ctrl-C を reduce し、buffer "" と suggestion nil を確かめている。次に打つ echo が実行できる状態に戻ることに当たる |
| `expected.exit_code` | 0 | `t/unit/test-input-state-commands.lisp:224` it "input-state-ctrl-d-empty-quits-but-non-empty-deletes" | 空の buffer で Ctrl-D を reduce すると :quit になることを確かめている。最後の C-d で終了することに当たる |

### J01-command-name

`t/scenarios/J01/command-name.json` [削除 (先にテストを足す)]

シナリオの入口: `nshell --no-config --command TEXT`（scripts/run-scenarios.py:1061、別プロセスの stdout と終了状態を見る）

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stdout.contains[0]` | "echo" | `t/unit/test-builtin-shell-extras.lisp:255` it "complete-C-lists-completions-for-the-given-line-one-per-line" | complete builtin を call-builtin で直接呼ぶ（--command・MAIN・バッチの終了状態を通らない） | いいえ | "ech" を渡して echo が出ることを見ているが、--command で `complete -C "ec"` を走らせた stdout ではない。 |
| `expected.exit_code` | 0 | `t/unit/test-builtin-shell-extras.lisp:255` it "complete-C-lists-completions-for-the-given-line-one-per-line" | complete builtin を call-builtin で直接呼ぶ（--command・MAIN・バッチの終了状態を通らない） | いいえ | builtin の戻り値 0 を見ており、プロセスの終了状態ではない。 |

### J02-same-second-directory-cache-invalidation

`t/scenarios/J02/J02-same-second-directory-cache-invalidation.json` [golden へ移す]

```json
{
  "env": {},
  "expected": {
    "duration_ms": 0,
    "effects": [],
    "nshell_api": 1,
    "ok": true,
    "safety": {
      "level": "confirm",
      "reasons": [
        {
          "rule": "classify/unknown-command",
          "text": "unknown command"
        }
      ]
    },
    "state": {
      "cwd": "$WORK",
      "env_changed": [],
      "jobs": []
    },
    "status": 0,
    "stderr": {
      "bytes": 0,
      "lines": 0,
      "text": "",
      "truncated": false
    },
    "stdout": {
      "bytes": 10,
      "lines": 1,
      "text": "fresh.txt\n",
      "truncated": false
    }
  },
  "files": {},
  "input": "touch -t 202001010101.00 .; complete -C 'cat fresh'; touch fresh.txt; touch -t 202001010101.00 .; complete -C 'cat fresh'"
}
```

この期待値は、aarch64-darwin でビルドした nshell に、golden の実行器と同じ作業ディレクトリ・環境・正規化で 3 回流し、`error.message` を除いた envelope 全体が 3 回とも一致したものです。Linux では流していません。

### J02-symlink-target-kind-cache-invalidation

`t/scenarios/J02/J02-symlink-target-kind-cache-invalidation.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.contains[0]` | "link_swap/" | `t/unit/test-filesystem-file-completion.lisp:488` it "reclassifies cached symlinks after external target changes" | 実ファイルシステムでリンク先をファイルからディレクトリに置き換え、候補が "external-link/" (:directory) に変わることを確かめている |
| `expected.stderr.equals` | "" | なし | complete -C が標準エラーに何も書かないことを確かめるテストはない。builtin のテストは出力文字列と code だけを見る |
| `expected.exit_code` | 0 | `t/unit/test-builtin-shell-extras.lisp:255` it "complete-C-lists-completions-for-the-given-line-one-per-line" | complete -C を呼んで code 0 を確かめている |

### J02-bare-file-completion

`t/scenarios/J02/bare-file-completion.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.contains[0]` | "space name.txt" | `t/unit/test-filesystem-file-completion.lisp:102` it "filesystem-candidate-insertion-preserves-spaces-and-unicode" | "cat spa" の補完で "space name.txt" の候補が出ることを確かめている (ファイル一覧は差し替え。名前の扱いは domain の性質なので対応とみなす) |
| `expected.stdout.contains[1]` | "日本語.txt" | `t/unit/test-filesystem-file-completion.lisp:102` it "filesystem-candidate-insertion-preserves-spaces-and-unicode" | "cat 日" の補完で "日本語.txt" の候補が出ることを確かめている |
| `expected.stdout.contains[2]` | "ordinary.txt" | `t/unit/test-filesystem-file-completion.lisp:4` it "bare-filename-prefixes-include-files-and-knowledge-base-candidates" | "tool f" の補完で通常のファイル "file.txt" が候補に入ることを確かめている |
| `expected.stdout.contains[3]` | "folder/" | `t/unit/test-filesystem-file-completion.lisp:289` it "host port preserves kinds and ordered legacy candidates" | 実ファイルシステムで、ディレクトリ "target-dir/" が末尾 / 付きで候補に入ることを確かめている |
| `expected.stdout.contains[4]` | "file-link.txt" | `t/unit/test-filesystem-file-completion.lisp:289` it "host port preserves kinds and ordered legacy candidates" | 実ファイルシステムで、ファイルへのリンク "file-link" が候補に入ることを確かめている |
| `expected.stdout.contains[5]` | "directory-link/" | `t/unit/test-filesystem-file-completion.lisp:289` it "host port preserves kinds and ordered legacy candidates" | 実ファイルシステムで、ディレクトリへのリンクが "directory-link/" として候補に入ることを確かめている |
| `expected.stdout.contains[6]` | "broken-link" | `t/unit/test-filesystem-file-completion.lisp:289` it "host port preserves kinds and ordered legacy candidates" | 実ファイルシステムで、壊れたリンク "broken-link" が候補に入ることを確かめている |
| `expected.stdout.contains[7]` | ".hidden.txt" | `t/unit/test-filesystem-file-completion.lisp:289` it "host port preserves kinds and ordered legacy candidates" | 実ファイルシステムで、接頭辞 "." のときに ".hidden-file" が候補に入ることを確かめている |
| `expected.stdout.contains[8]` | ".hidden-dir/" | `t/unit/test-filesystem-file-completion.lisp:289` it "host port preserves kinds and ordered legacy candidates" | 実ファイルシステムで、接頭辞 "." のときに ".hidden-directory/" が候補に入ることを確かめている |
| `expected.stderr.equals` | "" | なし | complete -C が標準エラーに何も書かないことを確かめるテストはない |
| `expected.exit_code` | 0 | `t/unit/test-builtin-shell-extras.lisp:255` it "complete-C-lists-completions-for-the-given-line-one-per-line" | complete -C を呼んで code 0 を確かめている |

### J02-filename-insertion-pty

`t/scenarios/J02/filename-insertion-pty.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "J02_SPACE_INSERTION_OK" | `t/unit/test-filesystem-file-completion.lisp:102` it "filesystem-candidate-insertion-preserves-spaces-and-unicode" | "cat spa" の候補を apply-completion で挿入すると "cat space\\ name.txt" になることを確かめている。cat がこのファイルを読めることに当たる |
| `expected.stream.contains[1]` | "J02_UNICODE_INSERTION_OK" | なし | ; の後の 2 つ目のコマンドで、前に空白をエスケープした語がある行に Unicode の候補を挿入するテストはない。102 は 1 つ目のコマンドの "cat 日" だけを使う |
| `expected.exit_code` | 0 | なし | 2 つ目の挿入に対応するテストがないので、追加テストが最後まで通ることで代わりに確かめる |
| `steps[5].contains` | "J02_UNICODE_INSERTION_OK" | なし | contains[1] と同じ目印を待つ手順で、対応するテストがない |

### J02-filename-variants

`t/scenarios/J02/filename-variants.json` [削除 (先にテストを足す)]

シナリオの入口: `nshell --no-config --command TEXT`（scripts/run-scenarios.py:1061、別プロセスの stdout と終了状態を見る）。作業ディレクトリに plain.txt・.hidden.txt・space name.txt・café.txt を置く

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stdout.contains[0]` | "plain.txt" | `t/unit/test-filesystem-file-completion.lisp:4` it "bare-filename-prefixes-include-files-and-knowledge-base-candidates" | domain の補完関数を直接呼ぶ | いいえ | 接頭辞からファイルの候補が出ることを見ているが、--command の complete -C "cat plain" の stdout ではない。 |
| `expected.stdout.contains[1]` | ".hidden.txt" | `t/unit/test-filesystem-file-completion.lisp:289` it "host port preserves kinds and ordered legacy candidates" | infrastructure のファイルシステム port を直接呼ぶ | いいえ | 候補の種類と順序を見ているが、complete -C "cat ." で隠しファイルが出ることは確かめていない。 |
| `expected.stdout.contains[2]` | "space name.txt" | `t/unit/test-filesystem-file-completion.lisp:102` it "filesystem-candidate-insertion-preserves-spaces-and-unicode" | with-test-filesystem の偽のファイルシステムで補完関数を直接呼ぶ | いいえ | 空白をエスケープした挿入文字列を見ており、complete -C の出力に space name.txt が出ることは確かめていない。 |
| `expected.stdout.contains[3]` | "café.txt" | `t/unit/test-filesystem-file-completion.lisp:102` it "filesystem-candidate-insertion-preserves-spaces-and-unicode" | with-test-filesystem の偽のファイルシステムで補完関数を直接呼ぶ | いいえ | 非 ASCII の名前の扱いは見ているが、実ファイル café.txt を --command の complete -C で出すことは確かめていない。 |
| `expected.stdout.contains[4]` | "link.txt" | `t/unit/test-filesystem-file-completion.lisp:289` it "host port preserves kinds and ordered legacy candidates" | infrastructure のファイルシステム port を直接呼ぶ | いいえ | ファイルへのリンクの種類は見ているが、同じ --command の中で ln -s した link.txt が候補に出ることは確かめていない。 |
| `expected.exit_code` | 0 | `t/unit/test-builtin-shell-extras.lisp:255` it "complete-C-lists-completions-for-the-given-line-one-per-line" | complete builtin を call-builtin で直接呼ぶ（--command・MAIN・バッチの終了状態を通らない） | いいえ | builtin の戻り値 0 を見ており、5 つの complete -C と ln を続けたプロセスの終了状態ではない。 |

### J03-cd-and-cdpath

`t/scenarios/J03/cd-and-cdpath.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "J03_CDPATH_COMPLETION_OK" | なし | CDPATH の候補で補完した cd と cat の結果。CDPATH の候補生成 (engine.lisp:83-111) を確かめるテストは t/ にない |
| `expected.exit_code` | 0 | なし | 補完と cd・cat の後の exit が 0 になること。同じ流れを最後まで通すテストはない |
| `steps[5].contains` | "J03_CDPATH_COMPLETION_OK" | なし | expected.stream.contains[0] と同じ出力を待つ同期。対応するテストはない |

### J04-home-and-variable-path

`t/scenarios/J04/home-and-variable-path.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "J04_VARIABLE_PATH_OK" | なし | (cat $NOTE) の出力。S式の cat に相対パスの変数を渡して中身を出すテストは見つけていない |
| `expected.stream.contains[1]` | "J04_HOME_PATH_OK" | なし | cat ~/target/home- を Tab で補完して実行した出力。~ のファイル候補と実行を通すテストはない (test-completion-dynamic.lisp:51 はディレクトリ候補だけ) |
| `expected.exit_code` | 0 | なし | 流れ全体の後の exit が 0 になること。同じ流れを通すテストはない |
| `steps[3].contains` | "$TARGET/variable-note.txt" | なし | 一部だけ: `t/unit/test-completion-context.lisp:604` の it の 701-727 行が "(cat $TARGET/variable-)" の ) の前で complete-in-context が ("$TARGET/variable-note.txt") を返すことを確かめるが、TARGET は絶対パス "/home/user/target" で、ファイルシステムはモック。シナリオは相対値 "../home/target" を実ファイルシステムで引く |
| `steps[8].contains` | "J04_VARIABLE_PATH_OK" | なし | expected.stream.contains[0] と同じ出力を待つ。対応するテストはない |
| `steps[12].contains` | "J04_HOME_PATH_OK" | なし | expected.stream.contains[1] と同じ出力を待つ。対応するテストはない |

### J06-catalog-subcommands

`t/scenarios/J06/catalog-subcommands.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.contains[0]` | "status" | なし | 一部だけ: `t/unit/test-completion-builtins.lisp:182` が rule-complete で "git st" → status を確かめるが、seed した REPL の知識ベースに complete を呼ぶ経路ではない。jj st も確かめていない |
| `expected.stdout.contains[1]` | "build" | なし | nix b・cargo b の build を確かめるテストはない |
| `expected.stdout.contains[2]` | "ps" | なし | docker p の ps を確かめるテストはない (`t/unit/test-repl-completion-data.lisp:336` は docker --t だけ) |
| `expected.stdout.contains[3]` | "get" | なし | kubectl g の get を確かめるテストはない (同 366 行は kubectl apply --dr だけ) |
| `expected.stdout.contains[4]` | "install" | なし | npm i・pnpm i の install を確かめるテストはない |
| `expected.exit_code` | 0 | `t/unit/test-builtin-shell-extras.lisp:255` it "complete-C-lists-completions-for-the-given-line-one-per-line" | complete -C "ech" の終了コードが 0 であることを確かめる。シナリオの最後のコマンドも complete -C で、%builtin-complete は -C で常に 0 を返す (builtin-complete.lisp:93) |

### J07-ssh-hostname

`t/scenarios/J07/ssh-hostname.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.contains[0]` | "scenario-build-host" | なし | 176 は設定の行を文字列で渡し、196 は lister を差し替える。HOME の .ssh/config を読む %seed-ssh-hosts (`src/presentation/repl-completion-seed.lisp:74`) と、complete -C が HOME を渡す経路を通るテストがない |
| `expected.stdout.contains[1]` | "scenario-known-host" | なし | contains[0] と同じ。.ssh/known_hosts を読む部分を通るテストがない |
| `expected.stdout.excludes[0]` | "scenario-hashed" | `t/unit/test-completion-dynamic.lisp:176` it "parses-literal-ssh-hosts-and-skips-patterns-and-hashed-known-hosts" | ハッシュ済みの known_hosts 行 "\|1\|hashed-host" を含む入力の結果が、それを含まないリストに等しい。除外は解析の性質で、ファイルの読み込みに依らない |
| `expected.exit_code` | 0 | `t/unit/test-builtin-shell-extras.lisp:255` it "complete-C-lists-completions-for-the-given-line-one-per-line" | complete -C を呼んで code 0 を確かめている |

### J08-make-target

`t/scenarios/J08/make-target.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.contains[0]` | "scenario-test" | なし | 185 は Makefile の行を文字列で渡し、196 は lister を差し替える。cwd の Makefile を読む %seed-make-targets (`src/presentation/repl-completion-seed.lisp:79`) と、complete -C が cwd を渡す経路を通るテストがない |
| `expected.exit_code` | 0 | `t/unit/test-builtin-shell-extras.lisp:255` it "complete-C-lists-completions-for-the-given-line-one-per-line" | complete -C を呼んで code 0 を確かめている |

### J09-approx-kill-completion

`t/scenarios/J09/approx-kill-completion.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.contains[0]` | "-TERM" | `t/unit/test-completion-dynamic.lisp:216` it "completes-kill-signals-pids-and-usernames" | "kill -T" の補完で "-TERM" が候補に入ることを確かめている。シグナル名の候補は builtin が渡す値に依らない |
| `expected.stdout.contains[1]` | "-KILL" | なし | 216 は接頭辞 "-T" を使い、期待値は ("-TERM" "-TSTP" "-TTIN" "-TTOU") なので "-KILL" は出ない。"kill -" の候補を確かめるテストがない |
| `expected.exit_code` | 0 | `t/unit/test-builtin-shell-extras.lisp:255` it "complete-C-lists-completions-for-the-given-line-one-per-line" | complete -C を呼んで code 0 を確かめている |

### J10-environment-variable-name

`t/scenarios/J10/environment-variable-name.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.contains[0]` | "SCENARIO_COMPLETION_VALUE" | なし | test-completion-dynamic.lisp:4 は :variable-names を直接渡す。set で作った変数を complete -C が環境から集めて渡す経路 (`src/application/builtin-complete.lisp:17-22`) を通るテストがない |
| `expected.stdout.contains[1]` | "~scenario-user/" | なし | 216 は %username-completion-candidates を直接呼ぶ。"cd ~scenario" が complete を通って ~user の候補になる経路と、環境の USER を渡す経路を通るテストがない |
| `expected.exit_code` | 0 | `t/unit/test-builtin-shell-extras.lisp:255` it "complete-C-lists-completions-for-the-given-line-one-per-line" | complete -C を呼んで code 0 を確かめている |

### J11-wrapper-command-completion

`t/scenarios/J11/wrapper-command-completion.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.contains[0]` | "build" | なし | 一部だけ: `t/unit/test-completion-dynamic.lisp:232` は env cargo bu・xargs cargo の文脈 (コマンド名と接頭辞) を確かめるが、候補 build は確かめていない |
| `expected.stdout.contains[1]` | "status" | なし | nohup git st の展開も候補も確かめるテストはない |
| `expected.stdout.contains[2]` | "install" | なし | time npm in の展開も候補も確かめるテストはない |
| `expected.stdout.contains[3]` | "get" | なし | 一部だけ: test-completion-dynamic.lisp:232 は sudo -u 1234 kubectl ge の文脈だけで、候補 get は確かめていない |
| `expected.exit_code` | 0 | `t/unit/test-builtin-shell-extras.lisp:255` it "complete-C-lists-completions-for-the-given-line-one-per-line" | complete -C の終了コードが 0。シナリオの最後のコマンドも complete -C (builtin-complete.lisp:93) |

### J12-large-directory-completion

`t/scenarios/J12/large-directory-completion.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.contains[0]` | "entry_19999.txt" | なし | test-completion-context.lisp:570 は差し替えたファイル一覧で 20,000 件の候補数と probe 数を数える。実ディレクトリの 20,000 件を "./entry_" で読んで最後の entry_19999.txt が出ることは確かめない |
| `expected.stderr.equals` | "" | なし | complete -C が標準エラーに何も書かないことを確かめるテストはない |
| `expected.exit_code` | 0 | `t/unit/test-builtin-shell-extras.lisp:255` it "complete-C-lists-completions-for-the-given-line-one-per-line" | complete -C を呼んで code 0 を確かめている |

### J12-twenty-thousand-entry-directory

`t/scenarios/J12/twenty-thousand-entry-directory.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "J12_COMPLETION_READY" | なし | 20,000 件の実ディレクトリで complete -C "cat item-19999" が終わった後に出す目印。実ディレクトリでの complete -C を最後まで通すテストがない (test-completion-context.lisp:570 はファイル一覧を差し替える) |
| `expected.exit_code` | 0 | なし | contains[0] と同じ理由で、対応するテストがない |
| `steps[2].contains` | "J12_COMPLETION_READY" | なし | contains[0] と同じ目印を待つ同期で、対応するテストがない |

### J14-case-and-fuzzy-match

`t/scenarios/J14/case-and-fuzzy-match.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.contains[0]` | "status" | なし | 263 と 276 は %rank-candidates に候補を直接渡す。complete -c -a で登録した引数を complete -C "scenario-search STATUS" と "stt" で引く経路 (順位付けの前の絞り込みを含む) を通るテストがない |
| `expected.exit_code` | 0 | `t/unit/test-builtin-shell-extras.lisp:255` it "complete-C-lists-completions-for-the-given-line-one-per-line" | complete -C を呼んで code 0 を確かめている |

### J14-fuzzy-match-insertion-pty

`t/scenarios/J14/fuzzy-match-insertion-pty.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "J14_SEARCH_LINE status" | なし | 282 は candidate を手で作って apply-completion を呼ぶだけ。Tab で kb から部分列一致の候補を選んで挿入し、init.lisp の関数が "status" を受け取って実行されるまでを通すテストがない |
| `expected.exit_code` | 0 | なし | 主動作に対応するテストがないので、追加テストが最後まで通ることで代わりに確かめる |
| `steps[3].contains` | "J14_SEARCH_LINE status" | なし | contains[0] と同じ出力を待つ手順で、対応するテストがない |

### J15-sexp-context

`t/scenarios/J15/sexp-context.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "status" | なし | 閉じていない (progn (git st の中のコマンド島の文脈で git の候補 status を出すテストはない。`t/unit/test-completion-context.lisp:604` の (progn 系の case は空の文脈だけ |
| `expected.exit_code` | 0 | なし | C-c で行を捨てた後の exit が 0 になること。同じ流れを通すテストはない |
| `steps[2].contains` | "status" | なし | expected.stream.contains[0] と同じ候補表示を待つ。対応するテストはない |

### J16-approx-user-defined-completion

`t/scenarios/J16/approx-user-defined-completion.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "north" | なし | test-builtins-core-complete.lisp:4 と :103 は kb の候補と complete -C の出力を確かめるだけ。Tab で -a の候補 "north" が端末に描画されるか挿入されることを確かめるテストがない |
| `expected.exit_code` | 0 | なし | 主動作に対応するテストがないので、追加テストが最後まで通ることで代わりに確かめる |
| `steps[2].contains` | "J16_2" | なし | 前準備の目印を待つ同期。主動作に対応するテストがないので追加テストで代える |
| `steps[9].contains` | "J16_AFTER_2" | `t/unit/test-input-state-search-results.lisp:124` it "input-state-ctrl-c-clears-buffer" | (同期) 補完の候補を持つ状態で Ctrl-C を reduce し、buffer ""、候補の消去、:redraw を確かめている。次のコマンドが実行できる状態に戻ることに当たる |

### J17-approx-unknown-command-learning-responsiveness

`t/scenarios/J17/approx-unknown-command-learning-responsiveness.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "J17_SHELL_RESPONDED" | `t/unit/test-input-state-completion-session.lisp:166` it "completion-pager-reducer-ctrl-c-clears-input-before-next-command" | J17 と同じ "unknown-tool " のページャー状態で Ctrl-C、次のコマンドの貼り付け、Enter を順に reduce し、buffer の消去と :execute を確かめている |
| `expected.exit_code` | 0 | `t/unit/test-input-state-completion-session.lisp:166` it "completion-pager-reducer-ctrl-c-clears-input-before-next-command" | (同期) 主動作の Ctrl-C から次のコマンドの :execute までを通している |
| `steps[3].contains` | "AI 未起動" | なし | Ctrl-C の後のプロンプトで AI の状態が "AI 未起動" のまま描画されることを確かめるテストはない。test-prompt-rendering.lisp:75 は状態を差し替えて表示文字列を確かめ、test-completion-builtins.lisp:658 は help を取りに行かないことだけを確かめる |
| `steps[4].excludes[0]` | "tool" | なし | 166 はページャーの状態が nil になることだけを確かめる。描画したページャーの行 ("tool") を Ctrl-C の後に消すことを確かめるテストがない |
| `steps[7].contains` | "J17_SHELL_RESPONDED" | `t/unit/test-input-state-completion-session.lisp:166` it "completion-pager-reducer-ctrl-c-clears-input-before-next-command" | (同期) 次のコマンドの目印を待つ手順。166 が Ctrl-C から :execute までを通している |

### J17-ctrl-c-immediate-next-command

`t/scenarios/J17/ctrl-c-immediate-next-command.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "J17_IMMEDIATE_ECHO_RESPONDED" | なし | 166 は手で作ったページャー状態から始まり、Tab の :complete の処理を通らない。未知のコマンドで Tab を処理した直後に Ctrl-C を処理するテストはない。J13 ([残す]) の ctrl-c-clears-input は既知の echo を使うので、同じ入力ではない |
| `expected.exit_code` | 0 | なし | contains[0] と同じ理由で、対応するテストがない |
| `steps[5].contains` | "J17_IMMEDIATE_ECHO_RESPONDED" | なし | contains[0] と同じ目印を待つ手順で、対応するテストがない |

### J18-approx-completion-candidate-preview

`t/scenarios/J18/approx-completion-candidate-preview.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "preview-file.txt" | なし | test-input-state-completion-rendering.lisp:269 は :kind :file の絶対パスの候補を手で渡す。complete -a で登録した相対名 "preview-file.txt" を Tab で候補にして描画するテストはない |
| `expected.stream.contains[1]` | "J18_FILE_PREVIEW_CONTENT" | なし | contains[0] と同じ。complete -a の候補でファイルの中身 "J18_FILE_PREVIEW_CONTENT" のプレビューを描くテストがない |
| `expected.exit_code` | 0 | なし | 主動作に対応するテストがないので、追加テストが最後まで通ることで代わりに確かめる |
| `steps[4].contains` | "J18_2" | なし | 前準備の目印を待つ同期。主動作に対応するテストがないので追加テストで代える |
| `steps[8].excludes[0]` | "J18_FILE_PREVIEW_CONTENT" | なし | test-repl-rendering.lisp:83 は clear-rendered-completions を直接呼ぶだけで、Ctrl-C の処理からプレビューを消す経路を通らない |
| `steps[11].contains` | "J18_AFTER_2" | `t/unit/test-input-state-search-results.lisp:124` it "input-state-ctrl-c-clears-buffer" | (同期) 補完の候補を持つ状態で Ctrl-C を reduce し、buffer ""、候補の消去、:redraw を確かめている。次のコマンドが実行できる状態に戻ることに当たる |

### K01-command-existence-colors

`t/scenarios/K01/command-existence-colors.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "\u001b[1;38;5;203m" | なし | test-highlight.lisp:21 は未知のコマンドを :error に分類するだけ、test-theme-style.lisp:120 は青の rgb を 256 色にするだけで、:error の役割が "\e[1;38;5;203m" になることと、編集行の描画にそれが出ることを確かめるテストがない |
| `expected.exit_code` | 0 | `t/unit/test-input-state-commands.lisp:224` it "input-state-ctrl-d-empty-quits-but-non-empty-deletes" | 空の buffer で Ctrl-D を reduce すると :quit になることを確かめている。Ctrl-C の後の C-d で終了することに当たる |

### K02-existing-path-is-underlined

`t/scenarios/K02/existing-path-is-underlined.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "\u001b[4m" | なし | test-highlight.lisp:83 は *highlight-path-exists-p* を差し替えて :path に分類するだけ、test-theme-style.lisp:183 は :path を "\e[4m" にするだけ。実在する ./known-path.txt を含む編集行を描画して "\e[4m" が出ることを確かめるテストがない |
| `expected.exit_code` | 0 | なし | 主動作に対応するテストがないので、追加テストが最後まで通ることで代わりに確かめる |

### K03-redirection-target-is-not-an-error

`t/scenarios/K03/redirection-target-is-not-an-error.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "K03_2" | なし | 33 はリダイレクト先に絶対パスを使う。相対名 "redirected.txt" を cwd で解決して書いたファイルを cat で読むことを確かめるテストがない |
| `expected.stream.excludes[0]` | "command not found" | `t/unit/test-builtins-source-pipeline.lisp:33` it "source-pipeline-redirects-builtin-output" | builtin の echo をファイルにリダイレクトして output "" と code 0 を確かめている。"command not found" はコマンドが見つからないときだけ出る (`src/infrastructure/acl/syscall-process-resolution.lisp:16`) ので、code 0 はその不在を意味する |
| `expected.stream.excludes[1]` | "redirection target" | `t/unit/test-builtins-source-pipeline.lisp:33` it "source-pipeline-redirects-builtin-output" | src に "redirection target" を出す箇所はない。33 の output "" と code 0 は、リダイレクト先を誤りとして扱う出力がないことを意味する |
| `expected.exit_code` | 0 | `t/unit/test-builtins-source-pipeline.lisp:33` it "source-pipeline-redirects-builtin-output" | (同期) builtin の出力のリダイレクトを最後まで通し、code 0 を確かめている |
| `expected.side_effects.files[0].path` | "redirected.txt" | なし | 33 は絶対パスのリダイレクト先だけを使う。相対名を cwd で解決するテストがない |
| `expected.side_effects.files[0].exists` | true | なし | files[0].path と同じ |
| `expected.side_effects.files[0].contains[0]` | "K03_2" | なし | files[0].path と同じ。相対名のファイルに "K03_2" が書かれることを確かめるテストがない |
| `steps[4].contains` | "K03_2" | なし | contains[0] と同じ出力を待つ手順で、対応するテストがない |

### K04-unbalanced-parenthesis-diagnostic

`t/scenarios/K04/unbalanced-parenthesis-diagnostic.json` [削除 (先にテストを足す)]

シナリオの入口: 対話 REPL（scripts/run-scenarios.py が nshell を PTY で起動し、キー列を端末から送る → 行エディタ → Enter で提出 → 実行 → 端末への出力）。入力の間隔 0.12 秒、右プロンプト {time}

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "> " | `t/unit/test-repl-rendering-layout.lisp:149` it "repl-render-edit-buffer-styles-continuation-prompt" | render-edit-buffer を直接呼ぶ（キー入力と Enter を通らない） | いいえ | 2 行目の継続プロンプトの描画は見ているが、( で始まる未完の入力で Enter を押した後に端末へ "> " が出ることは確かめていない。 |
| `expected.exit_code` | 0 | `t/unit/test-input-state-continuation.lisp:31` it "K04-incomplete-parenthesis-enters-continuation-before-cancel" | reducer（reduce-once）と scan を直接呼ぶ | いいえ | 状態の遷移は見ているが、プロセスが Ctrl-D で終了コード 0 になることは確かめていない。 |
| `expected.side_effects.files[0].path` | "K04_SHOULD_NOT_EXIST" | `t/unit/test-input-state-continuation.lisp:31` it "K04-incomplete-parenthesis-enters-continuation-before-cancel" | reducer と scan を直接呼ぶ（実行を通らない） | いいえ | Ctrl-C で取り消した状態は見ているが、実行器が呼ばれず K04_SHOULD_NOT_EXIST が作られないことを実ファイルで確かめていない。 |
| `expected.side_effects.files[0].exists` | false | `t/unit/test-input-state-continuation.lisp:31` it "K04-incomplete-parenthesis-enters-continuation-before-cancel" | reducer と scan を直接呼ぶ（実行を通らない） | いいえ | 同上。 |
| `steps[2].contains` | ">" | `t/unit/test-repl-rendering-layout.lisp:149` it "repl-render-edit-buffer-styles-continuation-prompt" | render-edit-buffer を直接呼ぶ | いいえ | 画面に > が出るのを待つ同期は REPL の描画ループを通らないと確かめられない。 |
| `steps[6].contains` | "K04_AFTER_RECOVERED" | `t/unit/test-input-state-continuation.lisp:31` it "K04-incomplete-parenthesis-enters-continuation-before-cancel" | reducer と scan を直接呼ぶ（提出と実行を通らない） | いいえ | 取り消し後の入力を reducer で見ているが、printf K04_AFTER_%s RECOVERED を実行して K04_AFTER_RECOVERED が出ることは確かめていない。 |

### K05-string-highlighting

`t/scenarios/K05/string-highlighting.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "\u001b[38;5;" | なし | TERM=xterm-256color から :256 を選ぶ分岐 (`src/infrastructure/terminal/ansi.lisp:154`) を通すテストも、:256 で入力行を色付けするテストもない。test-theme-style.lisp:120 は depth を直接渡し、highlight の描画テスト (test-highlight.lisp:210) は :truecolor 固定 |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | PTY で起動した nshell に exit を送り、Goodbye! と終了コード 0 を確かめる |
| `steps[1].contains` | "K05_STRING_VALUE" | `t/unit/test-highlight.lisp:210` it "highlight-ansi-emits-one-reset-per-colored-span-and-none-for-empty" | 入力 echo hi を highlight->ansi で描画し、入力の文字がそのまま色付きで出ることを等値で確かめる (入力が描画に出るのを待つ同期) |

### K06-sexp-and-command-island-evaluation

`t/scenarios/K06/sexp-and-command-island-evaluation.json` [golden へ移す]

```json
{
  "env": {},
  "expected": {
    "duration_ms": 0,
    "effects": [],
    "nshell_api": 1,
    "ok": true,
    "safety": {
      "level": "confirm",
      "reasons": [
        {
          "rule": "classify/sexp-not-forced",
          "text": "S-expression command requires explicit force and has no redirects"
        },
        {
          "rule": "classify/unknown-command",
          "text": "unknown command"
        }
      ]
    },
    "state": {
      "cwd": "$WORK",
      "env_changed": [],
      "jobs": []
    },
    "status": 0,
    "stderr": {
      "bytes": 0,
      "lines": 0,
      "text": "",
      "truncated": false
    },
    "stdout": {
      "bytes": 22,
      "lines": 2,
      "text": "K06_COMMAND_ISLAND\n42\n",
      "truncated": false
    }
  },
  "files": {},
  "input": "(progn (echo K06_COMMAND_ISLAND) (+ 20 22))"
}
```

この期待値は、aarch64-darwin でビルドした nshell に、golden の実行器と同じ作業ディレクトリ・環境・正規化で 3 回流し、`error.message` を除いた envelope 全体が 3 回とも一致したものです。Linux では流していません。

削除の前に: `t/e2e/test-smoke-script.lisp:18` の it "e2e-main-script-executes-multiline-blocks" の隣に it を足す。with-temporary-output-file (path :prefix "nshell-k06-script") に、シナリオの invocation.text "(progn (echo K06_COMMAND_ISLAND) (+ 20 22))"（末尾改行なし）をそのまま書く。`t/e2e/test-smoke-script.lisp:372` の it "e2e-main-script-errexit-option-and-shell-command-delegation" と同じく `t/support/runtime.lisp:37` の %e2e-child-environment を使い、HOME を新しい空の一時ディレクトリに、PATH を "PATH=/usr/bin:/bin" に、TERM を "TERM=xterm-256color" に置き換えた環境を :environment に渡す（シナリオの environment.variables）。(%run-nshell-main (list path) :environment environment)（`t/e2e/test-smoke.lisp:60` の %run-nshell-main）の結果について、exit-code が 0、stdout に "K06_COMMAND_ISLAND" と "42" が含まれることを確かめる。シナリオは stderr を確かめないので、stderr "" を要求する %assert-nshell-main-result ではなく %run-nshell-main と expect で書く。

### K07-one-line-source-diagnostic

`t/scenarios/K07/one-line-source-diagnostic.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stderr.contains[0]` | "scenario.nsh:" | なし | e2e-main-script-stops-after-parse-error は stderr の syntax error しか見ず、スクリプトのパスが診断に出ることを確かめない。test-parser-diagnostics.lisp:407 は条件を手で作って format 関数に渡すだけで main の経路を通らない |
| `expected.stderr.contains[1]` | "syntax error" | `t/e2e/test-smoke-script.lisp:43` it "e2e-main-script-stops-after-parse-error" | 閉じない ( を含むスクリプトを %run-nshell-main で実行し、stderr に syntax error があることを確かめる |
| `expected.exit_code` | 1 | `t/e2e/test-smoke-script.lisp:43` it "e2e-main-script-stops-after-parse-error" | 同じ実行で終了コード 1 を確かめる |

### K08-macro-expansion-error-location

`t/scenarios/K08/macro-expansion-error-location.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stderr.contains[0]` | "scenario.nsh:2:1" | なし | test-sexp-evaluator.lisp:857 は条件の source-span と source-path の値を見るだけで、stderr の パス:2:1 表示は確かめない |
| `expected.stderr.contains[1]` | "K08_EXPANSION_ERROR" | なし | 同テストは cause の format-control が K08_EXPANSION_ERROR であることを見るが、stderr に出ることは確かめない |
| `expected.exit_code` | 1 | なし | マクロ展開エラーで止まるスクリプトの終了コードを確かめるテストはない |

### L01-left-and-right-prompt

`t/scenarios/L01/left-and-right-prompt.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "LEFT_L01" | なし | prompt builtin は apply handler をモックした test-prompt-format.lisp:153/:164 だけ、描画は *prompt-left-format* を直接束縛する test-prompt-rendering.lisp:177。builtin から実際の apply-prompt-format (`src/presentation/prompt-display.lisp:347`) を経て描画に出る経路を通すテストはない |
| `expected.stream.contains[1]` | "RIGHT_L01" | なし | prompt builtin は apply handler をモックした test-prompt-format.lisp:153/:164 だけ、描画は *prompt-left-format* を直接束縛する test-prompt-rendering.lisp:177。builtin から実際の apply-prompt-format (`src/presentation/prompt-display.lisp:347`) を経て描画に出る経路を通すテストはない (right も同じ) |
| `expected.stream.contains[2]` | "L01_PROMPT_READY" | `t/e2e/test-smoke.lisp:476` it "e2e-main-interactive-pty-status-survives-input-boundaries" | PTY の対話入力で printf を 2 回実行し、各出力と exit 後の終了コード 0 を確かめる (シナリオ自身が出す目印) |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | PTY で起動した nshell に exit を送り、Goodbye! と終了コード 0 を確かめる |
| `steps[2].contains` | "L01_2" | `t/e2e/test-smoke-script.lisp:176` it "e2e-main-command-expands-documented-core-forms" | --command で ; の後の echo arith=$((1 + 2 * 3)) が arith=7 を出すことを確かめる (シナリオ自身が出す目印) |
| `steps[5].contains` | "L01_3" | `t/e2e/test-smoke-script.lisp:176` it "e2e-main-command-expands-documented-core-forms" | --command で ; の後の echo arith=$((1 + 2 * 3)) が arith=7 を出すことを確かめる (シナリオ自身が出す目印) |
| `steps[8].contains` | "L01_PROMPT_READY" | `t/e2e/test-smoke.lisp:476` it "e2e-main-interactive-pty-status-survives-input-boundaries" | PTY の対話入力で printf を 2 回実行し、各出力と exit 後の終了コード 0 を確かめる (シナリオ自身が出す目印) |

### L02-slow-git-status-does-not-block-input

`t/scenarios/L02/slow-git-status-does-not-block-input.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | PTY で起動した nshell に exit を送り、Goodbye! と終了コード 0 を確かめる |
| `expected.stream.contains[0]` | "L02_SLOW_GIT_OUTPUT" | `t/e2e/test-smoke.lisp:476` it "e2e-main-interactive-pty-status-survives-input-boundaries" | PTY の対話入力で printf を 2 回実行し、各出力と exit 後の終了コード 0 を確かめる (シナリオ自身が出す目印) |
| `expected.side_effects.files[0].path` | "git-probe/calls.log" | なし | git の引数は test-prompt-domain.lisp:118 が *git-runner* をモックして見るだけで、実際の %run-git が PATH の git を -C DIR 付きで起動することは確かめない |
| `expected.side_effects.files[0].contains[0]` | "symbolic-ref --quiet --short HEAD" | なし | 同上 (symbolic-ref --quiet --short HEAD) |
| `expected.side_effects.files[0].contains[1]` | "status --porcelain" | なし | 同上 (status --porcelain) |
| `steps[1].contains` | "echo $NSHELL_L02_OUTPUT" | なし | git status が終わる前に入力が描かれることを確かめるテストはない。test-prompt-domain.lisp:216 は get-git-status がモックの runner の完了前に戻ることだけを見る |
| `steps[3].contains` | "L02_SLOW_GIT_OUTPUT" | なし | 同上。0.5 秒以内に出力が出ることは :216 (モックの runner、get-git-status 単体) だけで、プロンプト描画を含む経路では確かめない |
| `steps[5].contains` | "exit" | なし | 同上 (2 回目の描画でも入力が止まらないこと) |

### L03-status-duration-jobs-prompt-segments

`t/scenarios/L03/status-duration-jobs-prompt-segments.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "STATUS_" | なし | prompt builtin は apply handler をモックした test-prompt-format.lisp:153/:164 だけ、描画は *prompt-left-format* を直接束縛する test-prompt-rendering.lisp:177。builtin から実際の apply-prompt-format (`src/presentation/prompt-display.lisp:347`) を経て描画に出る経路を通すテストはない |
| `expected.stream.contains[1]` | "EXIT_" | なし | prompt builtin は apply handler をモックした test-prompt-format.lisp:153/:164 だけ、描画は *prompt-left-format* を直接束縛する test-prompt-rendering.lisp:177。builtin から実際の apply-prompt-format (`src/presentation/prompt-display.lisp:347`) を経て描画に出る経路を通すテストはない |
| `expected.stream.contains[2]` | "DURATION_" | なし | prompt builtin は apply handler をモックした test-prompt-format.lisp:153/:164 だけ、描画は *prompt-left-format* を直接束縛する test-prompt-rendering.lisp:177。builtin から実際の apply-prompt-format (`src/presentation/prompt-display.lisp:347`) を経て描画に出る経路を通すテストはない |
| `expected.stream.contains[3]` | "JOBS_" | なし | prompt builtin は apply handler をモックした test-prompt-format.lisp:153/:164 だけ、描画は *prompt-left-format* を直接束縛する test-prompt-rendering.lisp:177。builtin から実際の apply-prompt-format (`src/presentation/prompt-display.lisp:347`) を経て描画に出る経路を通すテストはない |
| `expected.exit_code` | 1 | `t/e2e/test-smoke.lisp:467` it "e2e-main-interactive-pty-exit-preserves-last-status" | false の後に exit を送り、終了コード 1 を確かめる |
| `steps[2].contains` | "L03_2" | `t/e2e/test-smoke-script.lisp:176` it "e2e-main-command-expands-documented-core-forms" | --command で ; の後の echo arith=$((1 + 2 * 3)) が arith=7 を出すことを確かめる (シナリオ自身が出す目印) |
| `steps[5].contains` | "STATUS_" | なし | false の後に描き直したプロンプトに prompt left で入れた形式のリテラルが出ることを確かめるテストはない (同上) |

### L04-approx-transient-prompt-keeps-current-prompt

`t/scenarios/L04/approx-transient-prompt-keeps-current-prompt.json` [削除 (先にテストを足す)]

シナリオの入口: 対話 REPL（scripts/run-scenarios.py が nshell を PTY で起動し、キー列を端末から送る → 行エディタ → Enter で提出 → 実行 → 端末への出力）

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "L04_SECOND" | `t/e2e/test-smoke.lisp:476` it "e2e-main-interactive-pty-status-survives-input-boundaries" | 実 PTY で nshell の MAIN を起動しキー入力を書き込む（%e2e-pty-spawn、--no-config --no-history） | はい | 2 回目以降の提出の出力が端末に届くことは見ているが、入力は printf と $status で、実行時の環境変数を echo "$VAR" で出す 2 回目の L04_SECOND ではない。 |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:476` it "e2e-main-interactive-pty-status-survives-input-boundaries" | 実 PTY で nshell の MAIN を起動しキー入力を書き込む（%e2e-pty-spawn、--no-config --no-history） | はい | exit と改行を送り %assert-pty-child-exit で終了コード 0 を確かめている（同じ入口・同じ assertion）。 |
| `steps[2].contains` | "L04_FIRST" | `t/e2e/test-smoke.lisp:476` it "e2e-main-interactive-pty-status-survives-input-boundaries" | 実 PTY で nshell の MAIN を起動しキー入力を書き込む（%e2e-pty-spawn、--no-config --no-history） | はい | 1 回目の提出の出力は見ているが、入力は false と printf で echo "$SCENARIO_VALUE_A" ではない。 |
| `steps[5].contains` | "L04_SECOND" | `t/e2e/test-smoke.lisp:476` it "e2e-main-interactive-pty-status-survives-input-boundaries" | 実 PTY で nshell の MAIN を起動しキー入力を書き込む（%e2e-pty-spawn、--no-config --no-history） | はい | contains[0] と同じで、2 回目の echo "$VAR" の出力ではない。 |

### L05-approx-custom-prompt-format

`t/scenarios/L05/approx-custom-prompt-format.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "CUSTOM_" | なし | prompt builtin は apply handler をモックした test-prompt-format.lisp:153/:164 だけ、描画は *prompt-left-format* を直接束縛する test-prompt-rendering.lisp:177。builtin から実際の apply-prompt-format (`src/presentation/prompt-display.lisp:347`) を経て描画に出る経路を通すテストはない |
| `expected.stream.contains[1]` | "L05_CUSTOM_PROMPT" | `t/e2e/test-smoke.lisp:476` it "e2e-main-interactive-pty-status-survives-input-boundaries" | PTY の対話入力で printf を 2 回実行し、各出力と exit 後の終了コード 0 を確かめる (シナリオ自身が出す目印) |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | PTY で起動した nshell に exit を送り、Goodbye! と終了コード 0 を確かめる |
| `steps[2].contains` | "CUSTOM_" | なし | prompt builtin は apply handler をモックした test-prompt-format.lisp:153/:164 だけ、描画は *prompt-left-format* を直接束縛する test-prompt-rendering.lisp:177。builtin から実際の apply-prompt-format (`src/presentation/prompt-display.lisp:347`) を経て描画に出る経路を通すテストはない |
| `steps[5].contains` | "CUSTOM_" | なし | prompt builtin は apply handler をモックした test-prompt-format.lisp:153/:164 だけ、描画は *prompt-left-format* を直接束縛する test-prompt-rendering.lisp:177。builtin から実際の apply-prompt-format (`src/presentation/prompt-display.lisp:347`) を経て描画に出る経路を通すテストはない (echo の後の再描画) |

### L06-approx-narrow-terminal-redraw

`t/scenarios/L06/approx-narrow-terminal-redraw.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "L06_LONG_LINE_REDRAW" | なし | Home の後に End して Enter した行がそのまま実行されることを 1 つで確かめるテストはない。Home が buffer を変えないこと (test-input-state-core-properties.lisp:145)、End (test-input-state-navigation-properties.lisp:4)、ESC [H / ESC [F の解読 (test-terminal-stream.lisp:100)、幅より長いプロンプトの位置計算 (test-repl-rendering-layout.lisp:4) は別々のテスト |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | PTY で起動した nshell に exit を送り、Goodbye! と終了コード 0 を確かめる |
| `steps[4].contains` | "L06_LONG_LINE_REDRAW" | なし | Home の後に End して Enter した行がそのまま実行されることを 1 つで確かめるテストはない。Home が buffer を変えないこと (test-input-state-core-properties.lisp:145)、End (test-input-state-navigation-properties.lisp:4)、ESC [H / ESC [F の解読 (test-terminal-stream.lisp:100)、幅より長いプロンプトの位置計算 (test-repl-rendering-layout.lisp:4) は別々のテスト |

### L07-theme-can-be-selected

`t/scenarios/L07/theme-can-be-selected.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.contains[0]` | "nshell" | なし | test-builtin-theme.lisp:56 は theme show の出力に command と 5fafff --bold があることだけを見て、先頭行のテーマ名を見ない。theme use は :13 で handler をモックしている |
| `expected.stdout.contains[1]` | "prompt-path" | なし | theme show が prompt-path の役割を列挙することを確かめるテストはない |
| `expected.exit_code` | 0 | なし | 実際の handler (apply-repl-theme, `src/presentation/repl-batch.lisp:36`) で theme use の後に theme show を実行し成功することを確かめるテストはない |

### M01-cd-dash

`t/scenarios/M01/cd-dash.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.exit_code` | 0 | なし | cd の単体テスト (test-builtins-core-io.lisp:102) は host-kit:chdir と getcwd をモックする。実際に作業ディレクトリが変わり、後の外部コマンドやリダイレクトがそこで動くことを確かめるテストはない (e2e・integration に cd を使うテストはない) |
| `expected.side_effects.files[0].path` | "first/returned.txt" | なし | cd の単体テスト (test-builtins-core-io.lisp:102) は host-kit:chdir と getcwd をモックする。実際に作業ディレクトリが変わり、後の外部コマンドやリダイレクトがそこで動くことを確かめるテストはない (e2e・integration に cd を使うテストはない) |
| `expected.side_effects.files[0].exists` | true | なし | cd の単体テスト (test-builtins-core-io.lisp:102) は host-kit:chdir と getcwd をモックする。実際に作業ディレクトリが変わり、後の外部コマンドやリダイレクトがそこで動くことを確かめるテストはない (e2e・integration に cd を使うテストはない) |

### M02-logical-pwd-and-pwd-variable

`t/scenarios/M02/logical-pwd-and-pwd-variable.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.exit_code` | 0 | なし | cd の単体テスト (test-builtins-core-io.lisp:102) は host-kit:chdir と getcwd をモックする。実際に作業ディレクトリが変わり、後の外部コマンドやリダイレクトがそこで動くことを確かめるテストはない (e2e・integration に cd を使うテストはない) |
| `expected.side_effects.files[0].path` | "logical.txt" | なし | cd の単体テスト (test-builtins-core-io.lisp:102) は host-kit:chdir と getcwd をモックする。実際に作業ディレクトリが変わり、後の外部コマンドやリダイレクトがそこで動くことを確かめるテストはない (e2e・integration に cd を使うテストはない) (ファイルが cwd の work にできること) |
| `expected.side_effects.files[0].exists` | true | `t/unit/test-builtins-core-io.lisp:102` it "cd-maintains-logical-pwd-and-supports-dash" | cd link/.. の後 PWD が論理パス /tmp になり、chdir にも論理パスが渡ることを等値で確かめる |
| `expected.side_effects.files[0].contains[0]` | "work" | `t/unit/test-builtins-core-io.lisp:102` it "cd-maintains-logical-pwd-and-supports-dash" | PWD と OLDPWD を末尾 / のない値と等値で比べるので、work/ のような末尾 / がないことも確かめる |
| `expected.side_effects.files[0].excludes[0]` | "work/>" | なし | cd の単体テスト (test-builtins-core-io.lisp:102) は host-kit:chdir と getcwd をモックする。実際に作業ディレクトリが変わり、後の外部コマンドやリダイレクトがそこで動くことを確かめるテストはない (e2e・integration に cd を使うテストはない) |

### M03-directory-history-prevd-nextd

`t/scenarios/M03/directory-history-prevd-nextd.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.exit_code` | 0 | なし | cd の単体テスト (test-builtins-core-io.lisp:102) は host-kit:chdir と getcwd をモックする。実際に作業ディレクトリが変わり、後の外部コマンドやリダイレクトがそこで動くことを確かめるテストはない (e2e・integration に cd を使うテストはない) |
| `expected.side_effects.files[0].path` | "visits.txt" | なし | cd の単体テスト (test-builtins-core-io.lisp:102) は host-kit:chdir と getcwd をモックする。実際に作業ディレクトリが変わり、後の外部コマンドやリダイレクトがそこで動くことを確かめるテストはない (e2e・integration に cd を使うテストはない) |
| `expected.side_effects.files[0].exists` | true | なし | cd の単体テスト (test-builtins-core-io.lisp:102) は host-kit:chdir と getcwd をモックする。実際に作業ディレクトリが変わり、後の外部コマンドやリダイレクトがそこで動くことを確かめるテストはない (e2e・integration に cd を使うテストはない) |
| `expected.side_effects.files[0].contains[0]` | "a" | なし | prevd/nextd の単体テスト (test-builtin-shell-extras.lisp:129) は pushd で履歴を作り chdir をモックする。cd で積んだ履歴を辿り、pwd の出力がファイルに入ることは確かめない |
| `expected.side_effects.files[0].contains[1]` | "b" | なし | 同上 |

### M05-pushd-popd-stack-round-trip

`t/scenarios/M05/pushd-popd-stack-round-trip.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.exit_code` | 0 | なし | cd の単体テスト (test-builtins-core-io.lisp:102) は host-kit:chdir と getcwd をモックする。実際に作業ディレクトリが変わり、後の外部コマンドやリダイレクトがそこで動くことを確かめるテストはない (e2e・integration に cd を使うテストはない) |
| `expected.side_effects.files[0].path` | "stack.txt" | なし | cd の単体テスト (test-builtins-core-io.lisp:102) は host-kit:chdir と getcwd をモックする。実際に作業ディレクトリが変わり、後の外部コマンドやリダイレクトがそこで動くことを確かめるテストはない (e2e・integration に cd を使うテストはない) |
| `expected.side_effects.files[0].exists` | true | なし | cd の単体テスト (test-builtins-core-io.lisp:102) は host-kit:chdir と getcwd をモックする。実際に作業ディレクトリが変わり、後の外部コマンドやリダイレクトがそこで動くことを確かめるテストはない (e2e・integration に cd を使うテストはない) |
| `expected.side_effects.files[0].contains[0]` | "a" | なし | pushd/popd の単体テスト (test-builtin-shell-extras.lisp:62) は絶対パスを 1 回 pushd して popd し、chdir をモックする。相対パスで 2 回積んで popd した後の実際の cwd は確かめない |

### N01-session-variable

`t/scenarios/N01/session-variable.json` [削除 (先にテストを足す)]

シナリオの入口: `nshell --no-config --command TEXT`（scripts/run-scenarios.py:1061、別プロセスの stdout と終了状態を見る）

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stdout.contains[0]` | "hello" | `t/e2e/test-smoke-script.lisp:352` it "e2e-main-eval-runs-in-the-current-context" | nshell の MAIN を別プロセスで `--command TEXT` 付きで起動（%assert-nshell-main-result、`t/e2e/test-smoke.lisp:60`） | はい | 同じ --command の入口だが、入力は eval 'set EVAL_VALUE ready'; echo $EVAL_VALUE で、トップレベルの bare-line の set の後に echo $VAR が hello を出すことは確かめていない。 |
| `expected.exit_code` | 0 | `t/e2e/test-smoke-script.lisp:352` it "e2e-main-eval-runs-in-the-current-context" | nshell の MAIN を別プロセスで `--command TEXT` 付きで起動（%assert-nshell-main-result、`t/e2e/test-smoke.lisp:60`） | はい | 同じ入口で終了状態 0 を確かめている。 |

### N02-export-reaches-child-process

`t/scenarios/N02/export-reaches-child-process.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.contains[0]` | "SCENARIO_EXPORTED_VALUE=exported" | なし | export の単体テスト (test-builtins-core-shell.lisp:113) は context の環境に値と export の印が付くことだけを見る。子プロセスに渡ることは probe export-env が set -x で確かめるが、export NAME=value の経路ではない |
| `expected.exit_code` | 0 | なし | export の後に外部コマンドを実行して成功することを確かめるテストはない |

### N03-colon-separated-path-list

`t/scenarios/N03/colon-separated-path-list.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.contains[0]` | "PATH=a:" | なし | test-builtins-core-shell.lisp:202 は分割済みの引数を set に渡して context の値を見る。$PATH を展開して先頭に a を足し、子の env に出ることは確かめない |
| `expected.stdout.contains[1]` | ":/usr/bin:/bin" | なし | 同上 (:/usr/bin:/bin の部分は $PATH の展開から来る) |
| `expected.exit_code` | 0 | なし | set -x PATH の後に env を実行して成功することを確かめるテストはない |

### N04-unset-removes-variable

`t/scenarios/N04/unset-removes-variable.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.contains[0]` | "1" | なし | unset で消えること (test-builtins-core-shell.lisp:135)、set --query が無い名前で 1 を返すこと (:154)、$status が直前の失敗を映すこと (`t/e2e/test-smoke.lisp:402`) は別々のテストで、unset の後の set -q の結果を $status で出すことを通しで確かめるテストはない |
| `expected.exit_code` | 0 | なし | 同上 (この並びの --command の終了コード 0) |

### N05-approx-lexical-let-scope

`t/scenarios/N05/approx-lexical-let-scope.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.contains[0]` | "inner" | なし | set したシェル変数を let が隠し、関数の中の echo $lexical_scope が inner を出すことを確かめるテストはない |
| `expected.stdout.contains[1]` | "outer" | なし | let の外で outer に戻ることを確かめるテストはない |
| `expected.exit_code` | 0 | なし | 同じスクリプトを最後まで流して 0 を確かめるテストはない |

### N07-status-and-pipeline-status

`t/scenarios/N07/status-and-pipeline-status.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.contains[0]` | "<0,1 0>" | なし | test-sexp-evaluator.lisp:1114 は builtin と前景実行をスタブにし、テスト自身が %record-pipeline-statuses を呼ぶ。区切りも ; で && ではない。e2e (`t/e2e/test-smoke.lisp:409`) は S式の (\| ...) で $pipestatus だけを見る |
| `expected.exit_code` | 0 | なし | bare-line の false \| true && ... のスクリプトの終了コードを確かめるテストはない |

### O01-bare-line-sugar

`t/scenarios/O01/O01-bare-line-sugar.json` [削除]

シナリオの入口: スクリプトモード（scripts/run-scenarios.py が scenario.nsh を書き、`nshell scenario.nsh` で起動して stdout と終了状態を見る）

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stdout.contains[0]` | "O01_SEXP_FORM_OK" | `t/spec/probes.lisp:217` it "language-probe case-cmd v0.7.0 baseline" | `NSHELL_BIN case.nsh` でスクリプトモードの nshell を起動し、stdout・stderr・終了状態を v0.7.0 の記録と比べる（`t/spec/support.lisp:281` %run-probe） | はい | スクリプト (echo Hello WORLD) の stdout を "Hello WORLD\n" と等値で比べ、S 式の echo が記号の引数をそのまま出すことを確かめている（fixture: `docs/design/conformance/language-probes-v0.7.0.json:86`）。 |
| `expected.stdout.contains[1]` | "O01_BARE_LINE_OK" | `t/spec/probes.lisp:217` it "language-probe bare-comment v0.7.0 baseline" | `NSHELL_BIN case.nsh` でスクリプトモードの nshell を起動し、stdout・stderr・終了状態を v0.7.0 の記録と比べる（`t/spec/support.lisp:281` %run-probe） | はい | スクリプトの bare-line `echo c2` などの stdout を "c1\nc2\n" と等値で比べている（fixture :569）。 |
| `expected.exit_code` | 0 | `t/spec/probes.lisp:217` it "language-probe defun-args v0.7.0 baseline" | `NSHELL_BIN case.nsh` でスクリプトモードの nshell を起動し、stdout・stderr・終了状態を v0.7.0 の記録と比べる（`t/spec/support.lisp:281` %run-probe） | はい | S 式の行と bare-line の行を同じスクリプトに並べ、両方を実行して終了状態 0 になることを確かめている（fixture :589）。 |

### O02-command-island-evaluation

`t/scenarios/O02/O02-command-island-evaluation.json` [削除 (先にテストを足す)]

シナリオの入口: スクリプトモード（scripts/run-scenarios.py が scenario.nsh を書き、`nshell scenario.nsh` で起動して stdout と終了状態を見る）

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stdout.contains[0]` | "preserved" | `t/spec/probes.lisp:217` it "language-probe set-builtin v0.7.0 baseline" | `NSHELL_BIN case.nsh` でスクリプトモードの nshell を起動し、stdout・stderr・終了状態を v0.7.0 の記録と比べる（`t/spec/support.lisp:281` %run-probe） | はい | (set x 1)(echo $x) の stdout を等値で見ているが、値は整数で、文字列リテラル "preserved" を set して $ で展開することは確かめていない（fixture :66）。 |
| `expected.stdout.contains[1]` | "5" | `t/spec/probes.lisp:217` it "language-probe progn-value v0.7.0 baseline" | `NSHELL_BIN case.nsh` でスクリプトモードの nshell を起動し、stdout・stderr・終了状態を v0.7.0 の記録と比べる（`t/spec/support.lisp:281` %run-probe） | はい | (echo ,(progn 1 2)) がコンマの島の値 2 を出すことは確かめているが、同じ echo に $o02_value と ,(+ 2 3) を並べた形ではない（fixture :909）。 |
| `expected.exit_code` | 0 | `t/spec/probes.lisp:217` it "language-probe set-builtin v0.7.0 baseline" | `NSHELL_BIN case.nsh` でスクリプトモードの nshell を起動し、stdout・stderr・終了状態を v0.7.0 の記録と比べる（`t/spec/support.lisp:281` %run-probe） | はい | 同じ入口で終了状態 0 を確かめている。 |

### O03-let-and-set

`t/scenarios/O03/O03-let-and-set.json` [削除 (先にテストを足す)]

シナリオの入口: スクリプトモード（scripts/run-scenarios.py が scenario.nsh を書き、`nshell scenario.nsh` で起動して stdout と終了状態を見る）

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stdout.contains[0]` | "inner" | `t/spec/probes.lisp:217` it "language-probe let-dollar v0.7.0 baseline" | `NSHELL_BIN case.nsh` でスクリプトモードの nshell を起動し、stdout・stderr・終了状態を v0.7.0 の記録と比べる（`t/spec/support.lisp:281` %run-probe） | はい | (let ((n 3)) (echo $n ,n)) で let の束縛を $ で参照することは確かめているが、束縛の値は整数で、文字列 "inner" ではない（fixture :246）。 |
| `expected.stdout.contains[1]` | "outer" | `t/spec/probes.lisp:217` it "language-probe set-builtin v0.7.0 baseline" | `NSHELL_BIN case.nsh` でスクリプトモードの nshell を起動し、stdout・stderr・終了状態を v0.7.0 の記録と比べる（`t/spec/support.lisp:281` %run-probe） | はい | トップレベルの set と $ の参照は確かめているが、値は整数で、let の後に文字列 "outer" を参照する形ではない（fixture :66）。 |
| `expected.exit_code` | 0 | `t/spec/probes.lisp:217` it "language-probe let-dollar v0.7.0 baseline" | `NSHELL_BIN case.nsh` でスクリプトモードの nshell を起動し、stdout・stderr・終了状態を v0.7.0 の記録と比べる（`t/spec/support.lisp:281` %run-probe） | はい | 同じ入口で終了状態 0 を確かめている。 |

### O04-control-forms

`t/scenarios/O04/O04-control-forms.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.contains[0]` | "O04_IF_OK" | `t/spec/probes.lisp:217` it "language-probe gt-if v0.7.0 baseline" | (if (> 2 1) (echo gt-yes) (echo gt-no)) のスクリプトの stdout が gt-yes\n と一致することを確かめる |
| `expected.stdout.contains[1]` | "O04_WHEN_OK" | `t/spec/probes.lisp:217` it "language-probe when-cmd-body v0.7.0 baseline" | (when t (echo w1) (echo w2)) の stdout が w1\nw2\n と一致することを確かめる |
| `expected.stdout.contains[2]` | "O04_UNLESS_OK" | なし | unless・cond の本体でコマンドを実行して出力するテストはない。test-sexp-evaluator.lisp:301 は値位置の (unless nil 9) と (cond ... (t 13)) だけ、e2e (test-smoke-script.lisp:125) に unless と cond はない |
| `expected.stdout.contains[3]` | "O04_COND_OK" | なし | unless・cond の本体でコマンドを実行して出力するテストはない。test-sexp-evaluator.lisp:301 は値位置の (unless nil 9) と (cond ... (t 13)) だけ、e2e (test-smoke-script.lisp:125) に unless と cond はない |
| `expected.stdout.contains[4]` | "O04_CASE_OK" | なし | e2e (test-smoke-script.lisp:125) は最初の節が当たる (case 1 ((1) (echo switched))) だけ、test-sexp-evaluator.lisp:301 は値位置。2 番目の節が当たり 1 番目の本体が走らないことを出力で確かめるテストはない |
| `expected.stdout.contains[5]` | "O04_LOOP_OK" | `t/spec/probes.lisp:217` it "language-probe dotimes-dollar v0.7.0 baseline" | (dotimes (i 2) (echo $i)) の stdout が 0\n1\n と一致することを確かめる |
| `expected.stdout.excludes[0]` | "O04_IF_WRONG" | `t/spec/probes.lisp:217` it "language-probe gt-if v0.7.0 baseline" | stdout が gt-yes\n と一致するので、else 側の gt-no が出ないことも確かめる |
| `expected.stdout.excludes[1]` | "O04_COND_WRONG" | なし | unless・cond の本体でコマンドを実行して出力するテストはない。test-sexp-evaluator.lisp:301 は値位置の (unless nil 9) と (cond ... (t 13)) だけ、e2e (test-smoke-script.lisp:125) に unless と cond はない |
| `expected.stdout.excludes[2]` | "O04_CASE_WRONG" | なし | e2e (test-smoke-script.lisp:125) は最初の節が当たる (case 1 ((1) (echo switched))) だけ、test-sexp-evaluator.lisp:301 は値位置。2 番目の節が当たり 1 番目の本体が走らないことを出力で確かめるテストはない |
| `expected.exit_code` | 0 | なし | 6 種の制御構文を並べたスクリプトの終了コードを確かめるテストはない |

### O05-nested-command-definitions

`t/scenarios/O05/O05-nested-command-definitions.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.contains[0]` | "O05_TOPLEVEL_OK" | `t/spec/probes.lisp:217` it "language-probe defun-args v0.7.0 baseline" | トップレベルの (defun f (a b) (echo a=$a b=$b)) を (f 1 2) で呼び、stdout a=1 b=2 を確かめる |
| `expected.stdout.contains[1]` | "O05_NESTED_OK" | なし | test-sexp-evaluator.lisp:631 は (when t (defun ...)) を同じ progn の中で値を返す関数として呼ぶだけで、echo をスタブにした境界 (%call-with-sexp-evaluator-test-boundaries, `t/unit/test-sexp-evaluator.lisp:58`) で評価するので、実際の stdout は確かめない。後のトップレベル形式から $name を echo する本体を呼ぶことは確かめない |
| `expected.exit_code` | 0 | なし | 入れ子の定義を含むスクリプトの終了コードを確かめるテストはない |

### O06-macro-expansion

`t/scenarios/O06/O06-macro-expansion.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.contains[0]` | "O06_MACRO_OK" | なし | test-sexp-evaluator.lisp:792 と :765 は展開後のコマンドの呼び出し回数を見るだけで、echo をスタブにした境界 (%call-with-sexp-evaluator-test-boundaries, `t/unit/test-sexp-evaluator.lisp:58`) で評価するので、実際の stdout は確かめない |
| `expected.exit_code` | 0 | なし | defmacro を使うスクリプトの終了コードを確かめるテストはない |

### O07-conditional-and-handler-case

`t/scenarios/O07/O07-conditional-and-handler-case.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.contains[0]` | "O07_HANDLER_OK" | なし | test-sexp-evaluator.lisp:341 は fail をスタブの builtin (status 7) にした境界で値 18 を見る。^ で強制した外部コマンドが見つからないときに COMMAND-FAILED の節が走り、echo が出力することは確かめない |
| `expected.stdout.excludes[0]` | "O07_FALSE_BRANCH_WRONG" | なし | test-sexp-evaluator.lisp:357 は test をスタブにした真の分岐だけを見る。(when (false) ...) の本体が走らないことを出力で確かめるテストはない (probe test-pos は it-fails) |
| `expected.exit_code` | 0 | なし | この 2 行のスクリプトの終了コードを確かめるテストはない |

### O07-interactive-command-failed-restart

`t/scenarios/O07/O07-interactive-command-failed-restart.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "Ignore and continue" | なし | メニュー文 (`src/presentation/repl-output-handlers.lisp:7`) を確かめるテストはない。test-command-failure.lisp:152 は helper (:14) が *standard-output* を文字列ストリームに捨てる (:27) |
| `expected.stream.contains[1]` | "O07_RESTART_CONTINUED_2" | `t/unit/test-command-failure.lisp:152` it "keeps reading until choice 1 is submitted, then continues the nested function" | キー 2・1・Enter を読ませ、選択 1 で関数の続きが実行され (continued-p)、結果が (nil 7) になることを確かめる (回復後にシナリオ自身が出す目印) |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:470` it "e2e-main-interactive-pty-ctrl-d-preserves-last-status" | Ctrl-D で直前の status を終了コードにすることを確かめる (false の後は 1)。シナリオは直前が成功した echo なので 0 |
| `steps[4].contains` | "Ignore and continue" | なし | メニュー文 (`src/presentation/repl-output-handlers.lisp:7`) を確かめるテストはない。test-command-failure.lisp:152 は helper (:14) が *standard-output* を文字列ストリームに捨てる (:27) |
| `steps[9].contains` | "O07_RESTART_CONTINUED_2" | `t/unit/test-command-failure.lisp:152` it "keeps reading until choice 1 is submitted, then continues the nested function" | 同上 |

### O08-structured-pipeline

`t/scenarios/O08/O08-structured-pipeline.json` [削除 (先にテストを足す)]

シナリオの入口: スクリプトモード（scripts/run-scenarios.py が scenario.nsh を書き、`nshell scenario.nsh` で起動して stdout と終了状態を見る）

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stdout.contains[0]` | "1" | `t/unit/test-execute-pipeline.lisp:1558` it "O08-lowercase-pipeline-operators-dispatch-through-reader" | read-submission と evaluate-reader-result-in-context を同じプロセスで直接呼ぶ（スクリプトのファイル読み込み、echo とコンマの島、stdout を通らない） | いいえ | -> の値を等値で見ているが、スクリプトの (echo ,(length ...)) が stdout に 1 を出すことは確かめていない。 |
| `expected.exit_code` | 0 | `t/unit/test-execute-pipeline.lisp:1558` it "O08-lowercase-pipeline-operators-dispatch-through-reader" | 評価関数を直接呼ぶ | いいえ | 評価の status は見ているが、スクリプトを実行したプロセスの終了状態ではない。v0.7.0 の probe value-pipe（fixture :699）は (echo ,(to-json (-> ...))) をスクリプトで実行すると失敗しており、入口の違いが結果を変えうる。 |

### O09-json-tsv-lines-conversion

`t/scenarios/O09/O09-json-tsv-lines-conversion.json` [削除 (先にテストを足す)]

シナリオの入口: スクリプトモード（scripts/run-scenarios.py が scenario.nsh を書き、`nshell scenario.nsh` で起動して stdout と終了状態を見る）

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stdout.contains[0]` | "Ada" | `t/spec/probes.lisp:217` it "language-probe json-roundtrip v0.7.0 baseline" | `NSHELL_BIN case.nsh` でスクリプトモードの nshell を起動し、stdout・stderr・終了状態を v0.7.0 の記録と比べる（`t/spec/support.lisp:281` %run-probe） | はい | (echo ,(to-json (from-json "{\"k\":[1,2]}"))) をスクリプトで実行し stdout を等値で見ている。from-json → to-json の往復をコンマの島で出す形は同じだが、値はシナリオの {"name":"Ada"} ではない（fixture :709）。 |
| `expected.stdout.contains[1]` | "name" | `t/unit/test-sexp-value-conversion.lisp:26` it "converts JSON objects and lists with explicit empty-container behavior" | to-json / from-json を直接呼ぶ | いいえ | 変換結果を等値で見ているが、スクリプトの 2 行目の to-tsv(from-tsv ...) が name を出すことは確かめていない。 |
| `expected.stdout.contains[2]` | "first" | `t/unit/test-sexp-value-conversion.lisp:55` it "O09-lowercase-conversion-api-dispatches-through-reader" | read-submission と評価関数を直接呼ぶ（スクリプトと stdout を通らない） | いいえ | 変換 API の名前解決を見ているが、スクリプトで from-lines(to-lines ...) を echo して first が出ることは確かめていない。 |
| `expected.stdout.contains[3]` | "second" | `t/unit/test-sexp-value-conversion.lisp:55` it "O09-lowercase-conversion-api-dispatches-through-reader" | read-submission と評価関数を直接呼ぶ | いいえ | 同上で、second が出ることは確かめていない。 |
| `expected.exit_code` | 0 | `t/unit/test-sexp-value-conversion.lisp:93` it "converts TSV rows and rejects malformed or unrepresentable data" | to-tsv / from-tsv を直接呼ぶ | いいえ | 関数の結果を見ており、3 行のスクリプトを実行したプロセスの終了状態ではない。 |

### O10-regex-and-string-library

`t/scenarios/O10/O10-regex-and-string-library.json` [削除 (先にテストを足す)]

シナリオの入口: スクリプトモード（scripts/run-scenarios.py が scenario.nsh を書き、`nshell scenario.nsh` で起動して stdout と終了状態を見る）

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stdout.contains[0]` | "nshell" | `t/unit/test-builtins-core-string.lisp:368` it "O10-string-builtin-matches-regular-expressions" | string builtin を with-builtins-context で直接呼ぶ（スクリプトの読み込み、bare-line の解析、引用符の扱い、stdout を通らない） | いいえ | "^a.b$" などの一致は見ているが、スクリプトの bare-line `string match -r "^[a-z]+$" nshell` が stdout に nshell を出すことは確かめていない。 |
| `expected.exit_code` | 0 | `t/unit/test-builtins-core-string.lisp:368` it "O10-string-builtin-matches-regular-expressions" | string builtin を直接呼ぶ | いいえ | builtin の戻り値 0 を見ており、スクリプトを実行したプロセスの終了状態ではない。 |

### O11-native-arithmetic

`t/scenarios/O11/O11-native-arithmetic.json` [削除]

シナリオの入口: スクリプトモード（scripts/run-scenarios.py が scenario.nsh を書き、`nshell scenario.nsh` で起動して stdout と終了状態を見る）

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stdout.contains[0]` | "18" | `t/spec/probes.lisp:217` it "language-probe progn-value v0.7.0 baseline" | `NSHELL_BIN case.nsh` でスクリプトモードの nshell を起動し、stdout・stderr・終了状態を v0.7.0 の記録と比べる（`t/spec/support.lisp:281` %run-probe） | はい | スクリプト (echo ,(progn 1 2)) の stdout を "2\n" と等値で比べ、コンマの島で評価した CL の整数を echo が出すことを確かめている（fixture :909）。* と + は CL の関数で、島の中の評価は同じ経路を通る。 |
| `expected.exit_code` | 0 | `t/spec/probes.lisp:217` it "language-probe progn-value v0.7.0 baseline" | `NSHELL_BIN case.nsh` でスクリプトモードの nshell を起動し、stdout・stderr・終了状態を v0.7.0 の記録と比べる（`t/spec/support.lisp:281` %run-probe） | はい | 同じ入口で終了状態 0 を確かめている。 |

### O12-comments

`t/scenarios/O12/O12-comments.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.contains[0]` | "O12_FORM_OK" | `t/spec/probes.lisp:217` it "language-probe sexp-comments v0.7.0 baseline" | (echo s1) ; c のスクリプトが後ろのコメントを無視して s1 を出すことを stdout の一致で確かめる |
| `expected.stdout.contains[1]` | "O12_AFTER_COMMENT_OK" | なし | probe sexp-comments の 2 行目は #\| \|# のブロックコメントで、; だけの行の後の形式を確かめるテストはない |
| `expected.stdout.excludes[0]` | "trailing comment" | `t/spec/probes.lisp:217` it "language-probe sexp-comments v0.7.0 baseline" | stdout が s1\ns2\n と一致するので、行末の ; c が出ないことも確かめる |
| `expected.stdout.excludes[1]` | "full-line comment" | なし | ; だけの行が出力されないことを確かめるテストはない (bare-line では ; で始まる行は不正 (`t/unit/test-sexp-scanner.lisp:34`) なので別の扱い) |
| `expected.exit_code` | 0 | なし | ; だけの行を含むスクリプトの終了コードを確かめるテストはない |

### O13-script-shebang-and-source

`t/scenarios/O13/approx-O13-script-shebang-and-source.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.contains[0]` | "O13_SOURCE_OK" | なし | test-builtins-source.lisp:303 は source-lines に #! 行を渡すだけで、main のスクリプト先頭の #! と S式の (source "相対パス") を通すテストはない。test-builtins-core-shell.lisp:325 は alias 展開 |
| `expected.exit_code` | 0 | なし | 同上 (このスクリプトの終了コード) |

### O14-function-directory-autoload

`t/scenarios/O14/O14-function-directory-autoload.json` [削除 (先にテストを足す)]

シナリオの入口: スクリプトモード（scripts/run-scenarios.py が scenario.nsh を書き、`nshell scenario.nsh` で起動して stdout と終了状態を見る）。HOME/.config/nshell/functions/o14_greet.nsh を置き、XDG_CONFIG_HOME は設定しない

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stdout.contains[0]` | "O14_AUTOLOAD_OK" | `t/unit/test-safe-mode.lisp:402` it "safe-mode-stops-function-autoloading-in-non-interactive-runs" | nshell::main を同じプロセスで呼び、%current-process-arguments をスクリプトのパスに差し替える（MAIN のスクリプトの入口は同じ。関数ディレクトリは XDG_CONFIG_HOME で指定） | はい | 自動読み込みした関数の本体が touch で目印のファイルを作ることを見ており、stdout は捨てている。HOME/.config 側の既定の場所から読み込んだ関数の echo が O14_AUTOLOAD_OK を出すことは確かめていない。 |
| `expected.exit_code` | 0 | `t/unit/test-safe-mode.lisp:402` it "safe-mode-stops-function-autoloading-in-non-interactive-runs" | nshell::main を同じプロセスで呼び、スクリプトのパスを引数にする | はい | *main-exit-function* に渡る終了状態 0 を確かめている。 |

### O15-asdf-library-load

`t/scenarios/O15/O15-asdf-library-load.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.contains[0]` | "O15_ASDF_OK" | なし | スクリプトから ASDF システムを読み込んで関数を呼ぶテストはない。`t/unit/test-sexp-evaluator.lisp` の evaluates-qualified-call-inside-materialized-host-form はパッケージ修飾の呼び出しだけ |
| `expected.exit_code` | 0 | なし | 同じスクリプトを最後まで流して 0 を確かめるテストはない |

### O16-preserve-case

`t/scenarios/O16/O16-preserve-case.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.contains[0]` | "-KeepCase" | なし | probe case-cmd は Hello WORLD の大小を保つが、- で始まる語の大小を保つことは確かめない |
| `expected.stdout.contains[1]` | "CaseSensitive.NSH" | なし | probe glob は小文字の *.txt だけで、大文字の拡張子のパターンが大文字の名前に一致することは確かめない |
| `expected.exit_code` | 0 | なし | このスクリプトの終了コードを確かめるテストはない |

### O17-force-external-command

`t/scenarios/O17/O17-force-external-command.json` [削除]

シナリオの入口: スクリプトモード（scripts/run-scenarios.py が scenario.nsh を書き、`nshell scenario.nsh` で起動して stdout と終了状態を見る）

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stdout.contains[0]` | "O17_EXTERNAL_OK" | `t/spec/probes.lisp:217` it "language-probe splice v0.7.0 baseline" | `NSHELL_BIN case.nsh` でスクリプトモードの nshell を起動し、stdout・stderr・終了状態を v0.7.0 の記録と比べる（`t/spec/support.lisp:281` %run-probe） | はい | スクリプト (^printf "[%s]" ,@(list 1 2 3)) の stdout を "[1][2][3]\n" と等値で比べ、^ を付けた外部の printf を実行してその出力が stdout に出ることを確かめている（fixture :799）。 |
| `expected.exit_code` | 0 | `t/spec/probes.lisp:217` it "language-probe splice v0.7.0 baseline" | `NSHELL_BIN case.nsh` でスクリプトモードの nshell を起動し、stdout・stderr・終了状態を v0.7.0 の記録と比べる（`t/spec/support.lisp:281` %run-probe） | はい | 同じ入口で終了状態 0 を確かめている。 |

### O18-alias-eval-and-string-execution

`t/scenarios/O18/O18-alias-eval-and-string-execution.json` [削除 (先にテストを足す)]

シナリオの入口: スクリプトモード（scripts/run-scenarios.py が scenario.nsh を書き、`nshell scenario.nsh` で起動して stdout と終了状態を見る）

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stdout.contains[0]` | "O18_ALIAS_OK" | `t/spec/probes.lisp:217` it "language-probe alias-sexp v0.7.0 baseline" | `NSHELL_BIN case.nsh` でスクリプトモードの nshell を起動し、stdout・stderr・終了状態を v0.7.0 の記録と比べる（`t/spec/support.lisp:281` %run-probe） | はい | alias ll 'echo LL' の後の bare-line 呼び出しを確かめているが、本体の中に二重引用符を含む 'echo "O18_ALIAS_OK"' の展開は確かめていない（fixture :679）。 |
| `expected.stdout.contains[1]` | "O18_EVAL_OK" | `t/spec/probes.lisp:217` it "language-probe eval-string v0.7.0 baseline" | `NSHELL_BIN case.nsh` でスクリプトモードの nshell を起動し、stdout・stderr・終了状態を v0.7.0 の記録と比べる（`t/spec/support.lisp:281` %run-probe） | はい | スクリプト (eval "echo E1") の stdout を等値で比べ、文字列の実行を確かめている（fixture :669）。形はシナリオと同じ。 |
| `expected.exit_code` | 0 | `t/spec/probes.lisp:217` it "language-probe eval-string v0.7.0 baseline" | `NSHELL_BIN case.nsh` でスクリプトモードの nshell を起動し、stdout・stderr・終了状態を v0.7.0 の記録と比べる（`t/spec/support.lisp:281` %run-probe） | はい | eval だけのスクリプトの終了状態 0 で、alias を含む 3 行のスクリプトの終了状態ではない。 |

### P01-xdg-init-file

`t/scenarios/P01/approx-P01-xdg-init-file.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "P01_XDG_INIT_OK" | なし | test-file-config.lisp:45 は上書きパスの bare-line (set -x) を、:194 は source-lines-to-stream をモックして読み込む順序を見るだけで、XDG の設定ファイルを読んだ結果が起動時に stdout へ出ることは確かめない |
| `expected.stream.contains[1]` | "42" | なし | 対話で入力した (format t ...) の出力を確かめるテストはない。probe format-top はスクリプト、test-repl-submission.lisp:144 は関数本体の format t |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:470` it "e2e-main-interactive-pty-ctrl-d-preserves-last-status" | Ctrl-D で直前の status を終了コードにすることを確かめる (false の後は 1)。シナリオは直前が成功した echo なので 0 |
| `steps[4].contains` | "P01_SYNC_17" | `t/e2e/test-smoke.lisp:476` it "e2e-main-interactive-pty-status-survives-input-boundaries" | PTY の対話入力で printf を 2 回実行し、各出力と exit 後の終了コード 0 を確かめる (シナリオ自身が出す目印) |

### P02-conf-d-order

`t/scenarios/P02/approx-P02-conf-d-order.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "P02_INIT_OK" | なし | test-file-config.lisp:45 は上書きパスの bare-line (set -x) を、:194 は source-lines-to-stream をモックして読み込む順序を見るだけで、XDG の設定ファイルを読んだ結果が起動時に stdout へ出ることは確かめない |
| `expected.stream.contains[1]` | "P02_FIRST_OK" | なし | test-file-config.lisp:45 は上書きパスの bare-line (set -x) を、:194 は source-lines-to-stream をモックして読み込む順序を見るだけで、XDG の設定ファイルを読んだ結果が起動時に stdout へ出ることは確かめない |
| `expected.stream.contains[2]` | "P02_SECOND_OK" | なし | test-file-config.lisp:45 は上書きパスの bare-line (set -x) を、:194 は source-lines-to-stream をモックして読み込む順序を見るだけで、XDG の設定ファイルを読んだ結果が起動時に stdout へ出ることは確かめない |
| `expected.stream.contains[3]` | "P02_PROMPT_READY" | `t/e2e/test-smoke.lisp:476` it "e2e-main-interactive-pty-status-survives-input-boundaries" | PTY の対話入力で printf を 2 回実行し、各出力と exit 後の終了コード 0 を確かめる (シナリオ自身が出す目印) |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:470` it "e2e-main-interactive-pty-ctrl-d-preserves-last-status" | Ctrl-D で直前の status を終了コードにすることを確かめる (false の後は 1)。シナリオは直前が成功した echo なので 0 |
| `steps[2].contains` | "P02_PROMPT_READY" | `t/e2e/test-smoke.lisp:476` it "e2e-main-interactive-pty-status-survives-input-boundaries" | PTY の対話入力で printf を 2 回実行し、各出力と exit 後の終了コード 0 を確かめる (シナリオ自身が出す目印) |

### P03-function-directory

`t/scenarios/P03/approx-P03-function-directory.json` [削除 (先にテストを足す)]

シナリオの入口: 対話 REPL（scripts/run-scenarios.py が nshell を PTY で起動し、キー列を端末から送る → 行エディタ → Enter で提出 → 実行 → 端末への出力、設定を読み込む load_config true）。HOME/.config/nshell/functions/p03_greet.nsh を置く

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "P03_FUNCTION_DIRECTORY_OK" | `t/unit/test-repl-submission.lisp:157` it "e03-new-reader-refreshes-autoload-context-for-each-submission" | REPL の %evaluate-repl-reader-submission を直接呼び、XDG_CONFIG_HOME を *environment* に置く（起動時の設定読み込み、キー入力、端末を通らない） | いいえ | 提出ごとに関数ディレクトリを読み直すことは見ているが、PTY で p03_greet と入力し、既定の HOME/.config から読み込んだ関数の出力が端末に出ることは確かめていない。 |
| `expected.stream.contains[1]` | "P03_AFTER_2" | `t/e2e/test-smoke.lisp:476` it "e2e-main-interactive-pty-status-survives-input-boundaries" | 実 PTY で nshell の MAIN を起動しキー入力を書き込む（%e2e-pty-spawn、--no-config --no-history） | はい | 続く提出の出力が届くことは見ているが、--no-config で起動しており設定を読み込む起動ではなく、入力も echo $SCENARIO_MARKER ではない。 |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:470` it "e2e-main-interactive-pty-ctrl-d-preserves-last-status" | 実 PTY で nshell の MAIN を起動しキー入力を書き込む（%e2e-pty-spawn、--no-config --no-history） | はい | Ctrl-D で終了し直前の状態を終了コードにすることを見ているが、期待値は false の後の 1 で、設定を読み込んだ起動での 0 ではない。 |
| `steps[2].contains` | "P03_FUNCTION_DIRECTORY_OK" | `t/unit/test-repl-submission.lisp:157` it "e03-new-reader-refreshes-autoload-context-for-each-submission" | REPL の提出関数を直接呼ぶ | いいえ | contains[0] と同じで、端末で出力を待つ同期は確かめていない。 |
| `steps[5].contains` | "P03_AFTER_2" | `t/e2e/test-smoke.lisp:476` it "e2e-main-interactive-pty-status-survives-input-boundaries" | 実 PTY で nshell の MAIN を起動しキー入力を書き込む（%e2e-pty-spawn、--no-config --no-history） | はい | contains[1] と同じで、設定を読み込む起動での 2 回目の提出の出力ではない。 |

### P04-abbreviation-expansion

`t/scenarios/P04/approx-P04-abbreviation-expansion.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "P04_ABBR_OK" | なし | smoke-input.lisp:38 は表に直接入れた略語 say を Enter で展開・実行して hello を確かめ、:54 は :command 位置の展開だけ、test-builtins-core-shell.lisp:371 は -a -p の登録だけを確かめる。abbr 組み込みで登録した略語を Enter で展開し、展開後の $SCENARIO_MARKER を実行時に展開して出す一続きは確かめていない |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY の nshell に exit を送り Goodbye! と終了状態 0 を確かめる。exit が直前の状態を引き継ぐことは test-smoke.lisp:467 が確かめ、直前のコマンドの成功はこのシナリオの他の対応で確かめる |
| `steps[4].contains` | "P04_ABBR_OK" | なし | expected.stream.contains[0] と同じ理由で対応するテストはない |

### P05-alias-expansion

`t/scenarios/P05/P05-alias-expansion.json` [削除]

シナリオの入口: スクリプトモード（scripts/run-scenarios.py が scenario.nsh を書き、`nshell scenario.nsh` で起動して stdout と終了状態を見る）

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stdout.contains[0]` | "P05_ALIAS_OK" | `t/spec/probes.lisp:217` it "language-probe alias-sexp v0.7.0 baseline" | `NSHELL_BIN case.nsh` でスクリプトモードの nshell を起動し、stdout・stderr・終了状態を v0.7.0 の記録と比べる（`t/spec/support.lisp:281` %run-probe） | はい | スクリプト alias ll 'echo LL' の後の bare-line `ll` の stdout を等値で比べ、単一引用符の本体を持つ alias を bare-line で呼ぶことを確かめている（fixture :679）。シナリオと同じ形。 |
| `expected.exit_code` | 0 | `t/spec/probes.lisp:217` it "language-probe alias-sexp v0.7.0 baseline" | `NSHELL_BIN case.nsh` でスクリプトモードの nshell を起動し、stdout・stderr・終了状態を v0.7.0 の記録と比べる（`t/spec/support.lisp:281` %run-probe） | はい | 同じ入口で終了状態 0 を確かめている。 |

### P06-key-binding

`t/scenarios/P06/P06-key-binding.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "P06_BIND_OK" | なし | Ctrl-K で消した行の Enter の後に次のコマンドが動くことを確かめるテストはない |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY の nshell に exit を送り Goodbye! と終了状態 0 を確かめる。exit が直前の状態を引き継ぐことは test-smoke.lisp:467 が確かめ、直前のコマンドの成功はこのシナリオの他の対応で確かめる |
| `expected.side_effects.files[0].path` | "p06_should_not_run" | なし | test-builtin-bind.lisp:101 は bind ctrl-t clear-input で割り当ての種類が変わることだけ、test-input-state-search-results.lisp:124 は既定の Ctrl-C で非空のバッファが消えることだけを確かめる。bind で割り当てた ctrl-k をバッファ上で押して入力が消え、続く Enter で何も実行されないことは確かめていない |
| `expected.side_effects.files[0].exists` | false | なし | files[0].path と同じ理由で対応するテストはない |
| `steps[4].contains` | "P06_BIND_READY" | `t/unit/test-builtin-bind.lisp:101` it "bind-rebinds-a-key-to-a-different-action" | 同期用マーカー。bind <key> clear-input が終了コード 0 で終わることを確かめる。続く echo $VAR の出力は test-smoke-script.lisp:176 が確かめる |
| `steps[10].contains` | "P06_BIND_OK" | なし | expected.stream.contains[0] と同じ理由で対応するテストはない |

### P07-theme-selection

`t/scenarios/P07/P07-theme-selection.json` [golden へ移す]

```json
{
  "env": {},
  "expected": {
    "duration_ms": 0,
    "effects": [],
    "nshell_api": 1,
    "ok": true,
    "safety": {
      "level": "confirm",
      "reasons": [
        {
          "rule": "classify/unknown-command",
          "text": "unknown command"
        }
      ]
    },
    "state": {
      "cwd": "$WORK",
      "env_changed": [],
      "jobs": []
    },
    "status": 0,
    "stderr": {
      "bytes": 0,
      "lines": 0,
      "text": "",
      "truncated": false
    },
    "stdout": {
      "bytes": 1305,
      "lines": 37,
      "text": "nord\n  argument                normal\n  autosuggestion          4c566a\n  builtin                 81a1c1 --bold\n  command                 81a1c1 --bold\n  comment                 616e88 --italics\n  completion-command      81a1c1\n  completion-description  616e88\n  completion-directory    81a1c1 --bold\n  completion-file         normal\n  completion-more         616e88\n  completion-option       88c0d0\n  completion-selected     normal --reverse\n  completion-variable     a3be8c\n  error                   bf616a --bold\n  function                81a1c1 --bold\n  keyword                 b48ead --bold\n  normal                  normal\n  operator                d08770\n  option                  88c0d0\n  param                   normal\n  path                    normal --underline\n  prompt-assistant        616e88\n  prompt-continuation     616e88\n  prompt-duration         ebcb8b\n  prompt-error            bf616a --bold\n  prompt-git              b48ead\n  prompt-git-dirty        ebcb8b\n  prompt-host             a3be8c\n  prompt-ok               a3be8c --bold\n  prompt-path             81a1c1 --bold\n  prompt-time             616e88\n  quote                   ebcb8b\n  redirection             d08770\n  search-match            ebcb8b --bold\n  selection               normal --reverse\n  variable                a3be8c\n",
      "truncated": false
    }
  },
  "files": {},
  "input": "theme use nord; theme show"
}
```

この期待値は、aarch64-darwin でビルドした nshell に、golden の実行器と同じ作業ディレクトリ・環境・正規化で 3 回流し、`error.message` を除いた envelope 全体が 3 回とも一致したものです。Linux では流していません。

削除の前に: `t/e2e/test-smoke-script.lisp:18` の it "e2e-main-script-executes-multiline-blocks" の隣に it を足す。with-temporary-output-file (path :prefix "nshell-p07-script") に、シナリオの invocation.text "theme use nord\ntheme show\n" をそのまま書く。`t/e2e/test-smoke-script.lisp:372` の it "e2e-main-script-errexit-option-and-shell-command-delegation" と同じく `t/support/runtime.lisp:37` の %e2e-child-environment を使い、HOME を新しい空の一時ディレクトリに、PATH を "PATH=/usr/bin:/bin" に、TERM を "TERM=dumb" に置き換えた環境を :environment に渡す（シナリオの environment.variables）。(%run-nshell-main (list path) :environment environment)（`t/e2e/test-smoke.lisp:60` の %run-nshell-main）の結果について、exit-code が 0、stdout に "nord" が含まれることを確かめる。シナリオは stderr を確かめないので %assert-nshell-main-result は使わない。文字列中の \n は改行で、Lisp では (format nil "...~%...") などで書く。

### P08-prompt-format

`t/scenarios/P08/approx-P08-prompt-format.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "P08_CUSTOM_PROMPT_OK" | なし | test-prompt-format.lisp:153 は prompt left が handler に文字列を渡すことを lambda で受けて確かめ、test-prompt-rendering.lisp:210 は左書式 "ab> " の描画幅 4 だけを確かめる。実際の handler (apply-prompt-format) で入れた書式が描画の出力に文字列として出ることと、二重引用符の中の $SCENARIO_MARKER の展開は確かめていない |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY の nshell に exit を送り Goodbye! と終了状態 0 を確かめる。exit が直前の状態を引き継ぐことは test-smoke.lisp:467 が確かめ、直前のコマンドの成功はこのシナリオの他の対応で確かめる。prompt left が code 0 で終わることは test-prompt-format.lisp:153 が確かめる |
| `steps[2].contains` | "P08_CUSTOM_PROMPT_OK" | なし | expected.stream.contains[0] と同じ理由で対応するテストはない |

### P10-completion-definition

`t/scenarios/P10/P10-completion-definition.json` [golden へ移す]

```json
{
  "env": {},
  "expected": {
    "duration_ms": 0,
    "effects": [],
    "nshell_api": 1,
    "ok": true,
    "safety": {
      "level": "confirm",
      "reasons": [
        {
          "rule": "classify/unknown-command",
          "text": "unknown command"
        }
      ]
    },
    "state": {
      "cwd": "$WORK",
      "env_changed": [],
      "jobs": []
    },
    "status": 0,
    "stderr": {
      "bytes": 0,
      "lines": 0,
      "text": "",
      "truncated": false
    },
    "stdout": {
      "bytes": 13,
      "lines": 1,
      "text": "--p10-option\n",
      "truncated": false
    }
  },
  "files": {},
  "input": "complete -c p10_command -f --p10-option; complete -C \"p10_command --p10\""
}
```

この期待値は、aarch64-darwin でビルドした nshell に、golden の実行器と同じ作業ディレクトリ・環境・正規化で 3 回流し、`error.message` を除いた envelope 全体が 3 回とも一致したものです。Linux では流していません。

削除の前に: `t/e2e/test-smoke-script.lisp:18` の it "e2e-main-script-executes-multiline-blocks" の隣に it を足す。with-temporary-output-file (path :prefix "nshell-p10-script") に、シナリオの invocation.text "complete -c p10_command -f --p10-option\ncomplete -C \"p10_command --p10\"\n" をそのまま書く。`t/e2e/test-smoke-script.lisp:372` の it "e2e-main-script-errexit-option-and-shell-command-delegation" と同じく `t/support/runtime.lisp:37` の %e2e-child-environment を使い、HOME を新しい空の一時ディレクトリに、PATH を "PATH=/usr/bin:/bin" に、TERM を "TERM=dumb" に置き換えた環境を :environment に渡す（シナリオの environment.variables）。(%run-nshell-main (list path) :environment environment)（`t/e2e/test-smoke.lisp:60` の %run-nshell-main）の結果について、exit-code が 0、stdout に "--p10-option" が含まれることを確かめる。シナリオは stderr を確かめないので %assert-nshell-main-result は使わない。文字列中の \n は改行で、Lisp では (format nil "...~%...") などで書く。

### P11-continue-after-config-error

`t/scenarios/P11/approx-P11-continue-after-config-error.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "P11_CONFIG_LOADED" | なし | test-file-config.lisp:70 と :90 は load-config-sources を差し替えて、非 0 状態とエラーの報告文だけを確かめる。e2e の safe-flag テスト (test-safe-mode.lisp:60) は --safe で init.lisp を読まない。init.lisp の前半の出力が出て、後半の未定義関数で止まることは確かめていない |
| `expected.stream.contains[1]` | "42" | なし | 設定のエラーの後の同じセッションで (format t "~d~%" (* 6 7)) を評価して 42 が出ることを確かめるテストはない |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY の nshell に exit を送り Goodbye! と終了状態 0 を確かめる。exit が直前の状態を引き継ぐことは test-smoke.lisp:467 が確かめ、直前のコマンドの成功はこのシナリオの他の対応で確かめる |
| `steps[4].contains` | "P11_SYNC_17" | `t/e2e/test-smoke-script.lisp:176` it "e2e-main-command-expands-documented-core-forms" | 同期用マーカー。$((...)) の語中展開・$VAR の展開と echo の出力を --command 経路で最後まで走らせて確かめる |

### Q01-no-debug-dump

`t/scenarios/Q01/Q01-no-debug-dump.json` [golden へ移す]

```json
{
  "env": {},
  "expected": {
    "duration_ms": 0,
    "effects": [],
    "error": {
      "code": "E_PARSE",
      "message": "the input could not be parsed"
    },
    "nshell_api": 1,
    "ok": false,
    "safety": {
      "level": "block",
      "reasons": [
        {
          "rule": "classify/unparsable",
          "text": "the input could not be read"
        }
      ]
    },
    "state": {
      "cwd": "$WORK",
      "env_changed": [],
      "jobs": []
    },
    "status": 2,
    "stderr": {
      "bytes": 72,
      "lines": 1,
      "text": "nshell error: <input>: syntax error [0,1): Unsupported bare-line token.\n",
      "truncated": false
    },
    "stdout": {
      "bytes": 0,
      "lines": 0,
      "text": "",
      "truncated": false
    }
  },
  "files": {},
  "input": ")"
}
```

この期待値は、aarch64-darwin でビルドした nshell に、golden の実行器と同じ作業ディレクトリ・環境・正規化で 3 回流し、`error.message` を除いた envelope 全体が 3 回とも一致したものです。Linux では流していません。

削除の前に: `t/e2e/test-smoke-script.lisp:43` の it "e2e-main-script-stops-after-parse-error" の隣に it を足す。with-temporary-output-file (path :prefix "nshell-q01-script") に、シナリオの invocation.text ")\n" をそのまま書く。`t/e2e/test-smoke-script.lisp:372` の it "e2e-main-script-errexit-option-and-shell-command-delegation" と同じく `t/support/runtime.lisp:37` の %e2e-child-environment を使い、HOME を新しい空の一時ディレクトリに、PATH を "PATH=/usr/bin:/bin" に、TERM を "TERM=dumb" に置き換えた環境を :environment に渡す（シナリオの environment.variables）。(%run-nshell-main (list path) :environment environment)（`t/e2e/test-smoke.lisp:60` の %run-nshell-main）の結果について、exit-code が 2 であること、stdout と stderr のどちらにも "#S("、"Backtrace"、"SB-DEBUG" が含まれない（search が nil）ことを確かめる。stderr が空でないことに依存しないよう、%assert-nshell-main-result（stderr "" を要求する）は使わない。文字列中の \n は改行で、Lisp では (format nil "...~%...") などで書く。

### Q02-bounded-recursion-recovery

`t/scenarios/Q02/Q02-bounded-recursion-recovery.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "recursion" | なし | test-repl-execution.lisp:899 は関数表 (*functions*) に bare-line の本体を入れた q02_recurse を呼び、builtin-runtime.lisp:275 の :source-function の経路だけを通る。シナリオの (define-shell-function q02_recurse () (q02_recurse)) はシェル関数のレジストリに入り、:shell-function の経路 (builtin-runtime.lisp:318) と S 式の本体からの呼び出しを通るので、入力の種類が違う |
| `expected.stream.contains[1]` | "Q02_AFTER_2" | なし | 上と同じ理由で、S 式で定義した関数の再帰の後に回復することは確かめていない |
| `expected.stream.excludes[0]` | "Backtrace" | なし | test-repl-execution.lisp:899 は関数表 (*functions*) に bare-line の本体を入れた q02_recurse を呼び、builtin-runtime.lisp:275 の :source-function の経路だけを通る。シナリオの (define-shell-function q02_recurse () (q02_recurse)) はシェル関数のレジストリに入り、:shell-function の経路 (builtin-runtime.lisp:318) と S 式の本体からの呼び出しを通るので、入力の種類が違う。また 899 は *standard-output* だけを捕まえて不在を確かめる |
| `expected.stream.excludes[1]` | "#S(" | なし | excludes[0] と同じ理由で対応するテストはない |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY の nshell に exit を送り Goodbye! と終了状態 0 を確かめる。exit が直前の状態を引き継ぐことは test-smoke.lisp:467 が確かめ、直前のコマンドの成功はこのシナリオの他の対応で確かめる |
| `steps[6].contains` | "Q02_AFTER_2" | なし | expected.stream.contains[1] と同じ理由で対応するテストはない |

### Q04-cancel-completion

`t/scenarios/Q04/Q04-cancel-completion.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "ho" | なし | test-completion-builtins.lisp:73 は rule-complete "ec" の候補に echo があることだけ、e2e の Tab のテスト (test-smoke-input.lisp:4) は git の旗の補完だけを確かめる。"ec" で Tab を押して入力が echo に補完されることは確かめていない |
| `expected.stream.contains[1]` | "Q04_AFTER_CTRL_C_2" | `t/unit/test-input-state-search-results.lisp:124` it "input-state-ctrl-c-clears-buffer" | 補完中 (completion-index 1、base "a"、候補あり) の非空のバッファで Ctrl-C を押すとバッファが "" になり補完の状態が消えることを確かめる。続けて打った行が実行されることは test-input-state-completion-session.lisp:166 が pager の状態で確かめる |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY の nshell に exit を送り Goodbye! と終了状態 0 を確かめる。exit が直前の状態を引き継ぐことは test-smoke.lisp:467 が確かめ、直前のコマンドの成功はこのシナリオの他の対応で確かめる |
| `steps[2].contains` | "Q04_READY_2" | `t/e2e/test-smoke-script.lisp:176` it "e2e-main-command-expands-documented-core-forms" | 同期用マーカー。$((...)) の語中展開・$VAR の展開と echo の出力を --command 経路で最後まで走らせて確かめる |
| `steps[8].contains` | "Q04_AFTER_CTRL_C_2" | `t/unit/test-input-state-search-results.lisp:124` it "input-state-ctrl-c-clears-buffer" | expected.stream.contains[1] と同じ |

### Q05-git-probe-timeout-does-not-block-input

`t/scenarios/Q05/git-probe-timeout-does-not-block-input.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY の nshell に exit を送り Goodbye! と終了状態 0 を確かめる。exit が直前の状態を引き継ぐことは test-smoke.lisp:467 が確かめ、直前のコマンドの成功はこのシナリオの他の対応で確かめる |
| `expected.stream.contains[0]` | "Q05_GIT_PROBE_RESPONSE" | なし | test-prompt-domain.lisp:216 は *git-runner* をセマフォで止まる関数に差し替えて遅い symbolic-ref を模し、実際の git プロセスを起動しない。20 秒止まる実プロセスの git があってもコマンドが 2 秒以内に動くことは確かめていない。残す L02-git-prompt-responsiveness は status が遅い場合で、symbolic-ref が止まる場合ではない |
| `expected.side_effects.files[0].path` | "git-probe/calls.log" | なし | test-prompt-domain.lisp:118 は差し替えた *git-runner* が引数 ("symbolic-ref" "--quiet" "--short" "HEAD") を受けることを確かめるが、実際の git プロセスに渡る引数とその記録は確かめていない |
| `expected.side_effects.files[0].contains[0]` | "symbolic-ref --quiet --short HEAD" | なし | files[0].path と同じ理由で対応するテストはない |
| `steps[1].contains` | "echo $NSHELL_Q05_OUTPUT" | なし | git が止まっている間に打った入力が 2 秒以内に表示されることを確かめるテストはない。test-prompt-domain.lisp:216 は *git-runner* をセマフォで止まる関数に差し替えて遅い symbolic-ref を模し、実際の git プロセスを起動しない。20 秒止まる実プロセスの git があってもコマンドが 2 秒以内に動くことは確かめていない。残す L02-git-prompt-responsiveness は status が遅い場合で、symbolic-ref が止まる場合ではない |
| `steps[3].contains` | "Q05_GIT_PROBE_RESPONSE" | なし | expected.stream.contains[0] と同じ理由で対応するテストはない |
| `steps[5].contains` | "exit" | なし | steps[1].contains と同じ理由で対応するテストはない |

### Q08-normal-key-handler-remains-usable

`t/scenarios/Q08/normal-key-handler-remains-usable.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "Q08_NORMAL_OK" | なし | test-smoke-editing.lisp:32 は提案 " status" のある "git" での Ctrl-F を reducer だけで確かめる。REPL のキー処理 (%process-input-event) で空のバッファの Ctrl-F の後にコマンドが動くことは確かめていない |
| `expected.stream.excludes[0]` | "input processing failed; input was preserved" | なし | repl-execution.lisp:944 は故障を注入したときに文言が出ることを確かめ、通常の Ctrl-F で出ないことは確かめていない |
| `expected.stream.excludes[1]` | "Q08_TEST_CONDITION" | なし | 通常ビルドの src に Q08_TEST_CONDITION は無い (grep で該当なし) が、出力に出ないことを確かめるテストはない |
| `expected.stream.excludes[2]` | "Backtrace" | なし | repl-execution.lisp:944 は故障を注入したときに文言が出ることを確かめ、通常の Ctrl-F で出ないことは確かめていない。944 の Backtrace の不在の確認も故障注入時だけ |
| `expected.stream.excludes[3]` | "#S(" | なし | excludes[2] と同じ理由で対応するテストはない |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY の nshell に exit を送り Goodbye! と終了状態 0 を確かめる。exit が直前の状態を引き継ぐことは test-smoke.lisp:467 が確かめ、直前のコマンドの成功はこのシナリオの他の対応で確かめる |
| `steps[3].contains` | "Q08_NORMAL_OK" | なし | expected.stream.contains[0] と同じ理由で対応するテストはない |

### S01-ask-mode-cancel

`t/scenarios/S01/approx-S01-ask-mode-cancel.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "ask>" | `t/unit/test-repl-ask.lisp:138` it "renders-the-ask-suffix-and-includes-it-in-prompt-geometry" | mode :ask の入力状態で render-prompt-cont の出力に "ask>" が含まれることを確かめる。Ctrl-] で :ask に入ることは test-input-state-ask.lisp:4 が確かめる |
| `expected.stream.contains[1]` | "S01_AFTER_2" | なし | test-input-state-ask.lisp:37 は :ask での Ctrl-G と :ask-waiting での Ctrl-C だけを確かめる。:ask で入力の途中に Ctrl-C を押して元の入力に戻り、続くコマンドが動くことは確かめていない |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY の nshell に exit を送り Goodbye! と終了状態 0 を確かめる。exit が直前の状態を引き継ぐことは test-smoke.lisp:467 が確かめ、直前のコマンドの成功はこのシナリオの他の対応で確かめる |
| `steps[1].contains` | "ask>" | `t/unit/test-repl-ask.lisp:138` it "renders-the-ask-suffix-and-includes-it-in-prompt-geometry" | mode :ask の入力状態で render-prompt-cont の出力に "ask>" が含まれることを確かめる。Ctrl-] で :ask に入ることは test-input-state-ask.lisp:4 が確かめる |
| `steps[6].contains` | "S01_AFTER_2" | なし | expected.stream.contains[1] と同じ理由で対応するテストはない |

### S02-proposal-awaits-approval

`t/scenarios/S02/S02-proposal-awaits-approval.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "AI proposal" | なし | test-repl-ask.lisp:177 と :215 はパネルに "safe"・"confirm" の語があることだけを確かめ、見出しの "AI proposal" は確かめていない |
| `expected.stream.contains[1]` | "Goodbye!" | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY の nshell に exit を送り、出力に Goodbye! が出ることを確かめる |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY の nshell に exit を送り Goodbye! と終了状態 0 を確かめる。exit が直前の状態を引き継ぐことは test-smoke.lisp:467 が確かめ、直前のコマンドの成功はこのシナリオの他の対応で確かめる |
| `expected.side_effects.files[0].path` | "S02_APPROVED" | なし | test-assistant-approval.lisp:232 は提案を入れても承認の記録が nil であることだけを確かめ、実行の回数は数えない。test-repl-ask.lisp:409 は 1 回目の Enter で実行しないことを確かめるが、シナリオは Enter を押さずに Ctrl-C で取り消す。提案が届いてから Ctrl-C までに一度も実行しないことは確かめていない |
| `expected.side_effects.files[0].exists` | false | なし | files[0].path と同じ理由で対応するテストはない |
| `steps[3].contains` | "AI proposal" | なし | expected.stream.contains[0] と同じ理由で対応するテストはない |
| `steps[4].contains` | "(^touch S02_APPROVED)" | `t/unit/test-repl-ask.lisp:177` it "installs-a-safe-result-and-keeps-one-undo-step" | structured_output の command を入力行にそのまま入れる (バッファ "ls"、proposal-origin t) ことを確かめる。confirm の提案でも入れることは :215 が "rm file" で確かめる |
| `steps[5].files[0].path` | "S02_APPROVED" | なし | test-assistant-approval.lisp:232 は提案を入れても承認の記録が nil であることだけを確かめ、実行の回数は数えない。test-repl-ask.lisp:409 は 1 回目の Enter で実行しないことを確かめるが、シナリオは Enter を押さずに Ctrl-C で取り消す。提案が届いてから Ctrl-C までに一度も実行しないことは確かめていない |
| `steps[5].files[0].exists` | false | なし | steps[5].files[0].path と同じ理由で対応するテストはない |
| `steps[7].excludes[0]` | "(^touch S02_APPROVED)" | `t/unit/test-repl-ask.lisp:446` it "runs-a-typed-command-with-one-enter-after-ctrl-c-cancels-a-confirm-proposal" | 提案から入れた行で Ctrl-C を押してから l s を打つとバッファが "ls" に一致し、提案の文字列が消えることを確かめる |

### S03-explains-last-failure

`t/scenarios/S03/S03-explains-last-failure.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "The last command was false; it exited with status 1." | `t/unit/test-repl-ask.lisp:293` it "shows-explain-result-in-a-panel-without-replacing-the-edit-buffer" | explanation と structured_output.next_steps を持つ result を %handle-ask-model-event に渡し、explanation の本文がパネルの 1 行目に出て入力行を置き換えないことを確かめる |
| `expected.stream.contains[1]` | "S03_SHELL_ALIVE" | なし | 説明のパネルを Ctrl-C で閉じた後に打ったコマンドが動くことを確かめるテストはない (%process-explain-panel-event のテストは Tab だけ) |
| `expected.stream.contains[2]` | "Goodbye!" | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY の nshell に exit を送り、出力に Goodbye! が出ることを確かめる |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY の nshell に exit を送り Goodbye! と終了状態 0 を確かめる。exit が直前の状態を引き継ぐことは test-smoke.lisp:467 が確かめ、直前のコマンドの成功はこのシナリオの他の対応で確かめる |
| `expected.side_effects.files[0].path` | "S03_UNAPPROVED" | なし | 提案された次の手順が承認なしに実行されないことを実行の回数で確かめるテストはない。test-repl-ask.lisp:661 は入力行が変わらないことだけを確かめる |
| `expected.side_effects.files[0].exists` | false | なし | files[0].path と同じ理由で対応するテストはない |
| `steps[2].contains` | "[1 · ?]" | `t/unit/test-prompt-format.lisp:103` it "keeps-the-failure-explain-form-for-the-exit-segment" | {exit} の書式が failure-explain-p t のとき "[3 · ?]" になることを確かめる。false の後に failure-explain が有効になることは test-repl-execution.lisp:834 が確かめる |
| `steps[4].contains` | "The last command was false; it exited with status 1." | `t/unit/test-repl-ask.lisp:293` it "shows-explain-result-in-a-panel-without-replacing-the-edit-buffer" | explanation と structured_output.next_steps を持つ result を %handle-ask-model-event に渡し、explanation の本文がパネルの 1 行目に出て入力行を置き換えないことを確かめる |
| `steps[5].contains` | "touch S03_UNAPPROVED" | `t/unit/test-repl-ask.lisp:661` it "renders-explain-text-without-replacing-the-edit-buffer" | next_steps の command を番号付き ("1. ls") でパネルに出すことを確かめる |
| `steps[9].contains` | "S03_SHELL_ALIVE" | なし | expected.stream.contains[1] と同じ理由で対応するテストはない |

### S04-approves-agent-steps-individually

`t/scenarios/S04/S04-approves-agent-steps-individually.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "step 1/2" | なし | repl-agent.lisp:36 の "agent · step ~d/~d" を確かめるテストはない |
| `expected.stream.contains[1]` | "(^touch S04_FIRST)" | なし | agent のパネルに提案のコマンドを出すことを確かめるテストはない (:53 はパネルに "auto" が無いことだけ) |
| `expected.stream.contains[2]` | "step 2/2" | なし | repl-agent.lisp:36 の "agent · step ~d/~d" を確かめるテストはない |
| `expected.stream.contains[3]` | "(^touch S04_SECOND)" | なし | agent のパネルに提案のコマンドを出すことを確かめるテストはない (:53 はパネルに "auto" が無いことだけ) |
| `expected.stream.contains[4]` | "S04_SHELL_ALIVE" | `t/unit/test-agent-mode.lisp:393` it "skips-a-step-with-s-and-does-not-execute-the-rest" | s で手順を飛ばすと実行せず (dispatch 0 回)、*agent-session* が nil になって通常の入力に戻ることを確かめる |
| `expected.stream.contains[5]` | "Goodbye!" | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY の nshell に exit を送り、出力に Goodbye! が出ることを確かめる |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY の nshell に exit を送り Goodbye! と終了状態 0 を確かめる。exit が直前の状態を引き継ぐことは test-smoke.lisp:467 が確かめ、直前のコマンドの成功はこのシナリオの他の対応で確かめる |
| `expected.side_effects.files[0].path` | "S04_FIRST" | なし | test-agent-mode.lisp:117 と :343 は execute-command-node-in-context を差し替えて呼び出しの回数を数え、コマンドを実際には実行しない。(^touch S04_FIRST) が Enter の承認で実際にファイルを作ることは確かめていない |
| `expected.side_effects.files[0].exists` | true | なし | files[0].path と同じ理由で対応するテストはない |
| `expected.side_effects.files[1].path` | "S04_SECOND" | `t/unit/test-agent-mode.lisp:393` it "skips-a-step-with-s-and-does-not-execute-the-rest" | s で飛ばした手順の dispatch が 0 回であることを確かめる |
| `expected.side_effects.files[1].exists` | false | `t/unit/test-agent-mode.lisp:393` it "skips-a-step-with-s-and-does-not-execute-the-rest" | dispatch 0 回なので 2 つ目の手順のファイルは作られない |
| `steps[2].contains` | "(^touch S04_FIRST)" | なし | agent のパネルに提案のコマンドを出すことを確かめるテストはない (:53 はパネルに "auto" が無いことだけ) |
| `steps[3].files[0].path` | "S04_FIRST" | `t/unit/test-agent-mode.lisp:53` it "waits-for-a-key-before-dispatching-safe-model-steps" | model から手順を受け取っても、キーを押すまで dispatch が 0 回であることを確かめる |
| `steps[3].files[0].exists` | false | `t/unit/test-agent-mode.lisp:53` it "waits-for-a-key-before-dispatching-safe-model-steps" | 同上 |
| `steps[3].files[1].path` | "S04_SECOND" | `t/unit/test-agent-mode.lisp:53` it "waits-for-a-key-before-dispatching-safe-model-steps" | 同上 |
| `steps[3].files[1].exists` | false | `t/unit/test-agent-mode.lisp:53` it "waits-for-a-key-before-dispatching-safe-model-steps" | 同上 |
| `steps[5].contains` | "(^touch S04_SECOND)" | なし | agent のパネルに提案のコマンドを出すことを確かめるテストはない (:53 はパネルに "auto" が無いことだけ) |
| `steps[6].files[0].path` | "S04_FIRST" | なし | test-agent-mode.lisp:117 と :343 は execute-command-node-in-context を差し替えて呼び出しの回数を数え、コマンドを実際には実行しない。(^touch S04_FIRST) が Enter の承認で実際にファイルを作ることは確かめていない |
| `steps[6].files[0].exists` | true | なし | steps[6].files[0].path と同じ理由で対応するテストはない |
| `steps[6].files[1].path` | "S04_SECOND" | `t/unit/test-agent-mode.lisp:343` it "requires-fresh-enter-approval-for-the-next-step" | 1 回目の Enter の後、次の手順を受け取っても新しい Enter まで dispatch が 1 回のままであることを確かめる |
| `steps[6].files[1].exists` | false | `t/unit/test-agent-mode.lisp:343` it "requires-fresh-enter-approval-for-the-next-step" | 同上 |
| `steps[10].contains` | "S04_SHELL_ALIVE" | `t/unit/test-agent-mode.lisp:393` it "skips-a-step-with-s-and-does-not-execute-the-rest" | expected.stream.contains[4] と同じ |

### S05-noninteractive-ai-status

`t/scenarios/S05/S05-noninteractive-ai-status.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stdout.equals` | "AI is disabled in non-interactive sessions\n" | なし | test-ai-builtin.lisp:43 は interactive-terminal-p を nil に差し替えた下で、ai status の組み込みの出力がこの文字列と一致することを確かめる。スクリプト実行の stdout 全体 (ほかの出力が無いこと) と、実際の端末判定は確かめていない |
| `expected.exit_code` | 0 | `t/unit/test-ai-builtin.lisp:43` it "ai-status-does-not-start-the-sidecar-in-a-batch-session" | ai status の終了コード 0 を確かめる。バッチが最後の状態を終了状態にすることは test-repl.lisp:31 が確かめる |

### S06-classifies-and-gates-sexp-proposals

`t/scenarios/S06/S06-classifies-and-gates-sexp-proposals.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "AI proposal [safe]" | なし | test-repl-ask.lisp:177 はパネルに "safe" の語があることだけを確かめ、"AI proposal [safe]" の文字列は確かめていない |
| `expected.stream.contains[1]` | "S06 protected marker" | なし | test-assistant-approval.lisp:240 は safe の提案を 1 回の Enter で評価に渡すことを、評価を差し替えた記録で確かめる。(^cat S06_DELETE_TARGET/marker) を実際に実行して中身が出ることは確かめていない。(^cat FILE) を safe と判定することも test-assistant-safety.lisp:117 にない ((^ls) だけ) |
| `expected.stream.contains[2]` | "AI proposal [confirm]" | なし | test-repl-ask.lisp:215 はパネルに "confirm" の語があることだけを確かめる |
| `expected.stream.contains[3]` | "S06_SHELL_ALIVE" | `t/unit/test-repl-ask.lisp:446` it "runs-a-typed-command-with-one-enter-after-ctrl-c-cancels-a-confirm-proposal" | confirm の提案を Ctrl-C で取り消した後、打ったコマンドが 1 回の Enter で :typed として実行されることを確かめる |
| `expected.stream.contains[4]` | "Goodbye!" | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY の nshell に exit を送り、出力に Goodbye! が出ることを確かめる |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY の nshell に exit を送り Goodbye! と終了状態 0 を確かめる。exit が直前の状態を引き継ぐことは test-smoke.lisp:467 が確かめ、直前のコマンドの成功はこのシナリオの他の対応で確かめる |
| `expected.side_effects.files[0].path` | "S06_DELETE_TARGET/marker" | なし | Ctrl-C で取り消した confirm の提案を一度も実行せず、ファイルを残すことを実ファイルで確かめるテストはない。:446 は評価を差し替えて、打ったコマンドの実行が 1 回であることだけを確かめる。$PWD 下の絶対パスの (^rm -rf ...) を confirm と判定することも test-assistant-safety.lisp:117 にない (相対の marker-dir だけ) |
| `expected.side_effects.files[0].exists` | true | なし | files[0].path と同じ理由で対応するテストはない |
| `expected.side_effects.files[0].content.equals` | "S06 protected marker\n" | なし | files[0].path と同じ理由で対応するテストはない |
| `steps[3].contains` | "AI proposal [safe]" | なし | expected.stream.contains[0] と同じ理由で対応するテストはない |
| `steps[5].contains` | "S06 protected marker" | なし | expected.stream.contains[1] と同じ理由で対応するテストはない |
| `steps[9].contains` | "AI proposal [confirm]" | なし | expected.stream.contains[2] と同じ理由で対応するテストはない |
| `steps[13].contains` | "S06_SHELL_ALIVE" | `t/unit/test-repl-ask.lisp:446` it "runs-a-typed-command-with-one-enter-after-ctrl-c-cancels-a-confirm-proposal" | expected.stream.contains[3] と同じ |

### S07-shell-without-claude

`t/scenarios/S07/approx-S07-shell-without-claude.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "S07_NORMAL_2" | なし | agent の起動に失敗した後に通常のコマンドが動くことを確かめるテストはない |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY の nshell に exit を送り Goodbye! と終了状態 0 を確かめる。exit が直前の状態を引き継ぐことは test-smoke.lisp:467 が確かめ、直前のコマンドの成功はこのシナリオの他の対応で確かめる |
| `steps[2].contains` | "COMMAND-NOT-FOUND" | なし | test-assistant-model-boundary.lisp:1346 は run-sidecar-version-cancellable を (values nil :command-not-found) に差し替えて :stream-error の事象が届き message が公開前と同じであることを確かめるが、message の文字列 (assistant-sidecar-stream.lisp:412 の "assistant sidecar version probe failed: COMMAND-NOT-FOUND") と、agent がそれを表示することは確かめていない。:676 は状態 :unavailable だけ |
| `steps[5].contains` | "S07_NORMAL_2" | なし | expected.stream.contains[0] と同じ理由で対応するテストはない |

### S07-cancel-resumes-after-new-request

`t/scenarios/S07/cancel-resumes-after-new-request.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "agent: canceled" | なし | repl-agent.lisp:71 の "agent: ~a" (canceled) の表示を確かめるテストはない。test-repl-assistant-poll.lisp:171 は ask の待機中に Ctrl-C で stop-fn が 1 回呼ばれることだけを確かめる |
| `expected.stream.contains[1]` | "echo S07_CANCEL_RECOVERY_RESULT" | なし | 取り消しの後の新しい agent の要求で提案が表示されることを確かめるテストはない。test-assistant-model-boundary.lisp:55 は sidecar の状態で古い要求を止めることだけを確かめる |
| `expected.stream.contains[2]` | "S07_SHELL_ALIVE_AFTER_CANCEL" | `t/unit/test-agent-mode.lisp:420` it "cancels-an-agent-session-with-q" | q で agent のセッションを止め (stop-reason "canceled"、dispatch 0 回、*agent-session* nil)、通常の入力に戻ることを確かめる |
| `expected.stream.contains[3]` | "Goodbye!" | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY の nshell に exit を送り、出力に Goodbye! が出ることを確かめる |
| `expected.stream.excludes[0]` | "FAKE_CANCELED_STARTUP_FINISHED" | なし | 取り消した起動の version probe の出力 (3 秒後の FAKE_CANCELED_STARTUP_FINISHED) が後から表示されないことを確かめるテストはない |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY の nshell に exit を送り Goodbye! と終了状態 0 を確かめる。exit が直前の状態を引き継ぐことは test-smoke.lisp:467 が確かめ、直前のコマンドの成功はこのシナリオの他の対応で確かめる |
| `steps[2].contains` | "S07_FAKE_READY" | `t/e2e/test-signals.lisp:4` it "e2e-main-interactive-pty-ctrl-c-discards-pending-input" | 同期用マーカー。対話 PTY で打った printf の出力 (prompt-recovered:<yes>) が出ることを最後まで走らせて確かめる |
| `steps[5].contains` | "thinking" | `t/unit/test-repl-assistant-progress.lisp:4` it "shows-elapsed-seconds-while-the-model-is-thinking" | 待機中の進捗の行に "thinking… 1s" が出ることを確かめる |
| `steps[7].contains` | "agent: canceled" | なし | expected.stream.contains[0] と同じ理由で対応するテストはない |
| `steps[10].contains` | "echo S07_CANCEL_RECOVERY_RESULT" | なし | expected.stream.contains[1] と同じ理由で対応するテストはない |
| `steps[14].contains` | "S07_SHELL_ALIVE_AFTER_CANCEL" | `t/unit/test-agent-mode.lisp:420` it "cancels-an-agent-session-with-q" | expected.stream.contains[2] と同じ |

### T01-platform-support-matches-flake

`t/scenarios/T01/platform-support-matches-flake.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.exit_code` | 0 | なし | source モードの照合 (source_checks) が全部通ると 0。`flake.nix` と `docs/src/getting-started.md` のこの文字列を照合するテストはない |

### T02-etc-shells-guidance

`t/scenarios/T02/etc-shells-guidance.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.exit_code` | 0 | なし | source モードの照合 (source_checks) が全部通ると 0。`docs/src/getting-started.md` のこの手順を照合するテストはない |

### T03-help-output

`t/scenarios/T03/approx-T03-help-output.json` [削除 (先にテストを足す)]

シナリオの入口: スクリプトモード（scripts/run-scenarios.py が scenario.nsh を書き、`nshell scenario.nsh` で起動して stdout と終了状態を見る）

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stdout.contains[0]` | "echo" | `t/unit/test-builtins-core.lisp:74` it "help-renders-overview-and-command-specific-diagnostics" | help builtin を call-builtin で直接呼ぶ（スクリプトと stdout を通らない） | いいえ | 知識ベースの先頭の項目の synopsis を見ており、スクリプトの `help echo` が stdout に echo を出すことは確かめていない。 |
| `expected.exit_code` | 0 | `t/unit/test-builtins-core.lisp:74` it "help-renders-overview-and-command-specific-diagnostics" | help builtin を直接呼ぶ | いいえ | builtin の戻り値 0 を見ており、スクリプトを実行したプロセスの終了状態ではない。 |

### T05-legacy-history-load

`t/scenarios/T05/approx-T05-legacy-history-load.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "T05_HISTORY_IMPORTED_OK" | なし | test-file-history.lisp:491 は load-history-file が旧形式を取り込むことだけ、test-builtins-core-complete.lisp:129 は表に直接入れた履歴の search だけ、test-repl-execution.lisp:160 は load-history-file を差し替えて起動時に履歴へ入ることだけを確かめる。旧形式の履歴を起動時に取り込み、history search --contains imported (小文字の問い合わせ) で出す一続きは確かめていない |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY の nshell に exit を送り Goodbye! と終了状態 0 を確かめる。exit が直前の状態を引き継ぐことは test-smoke.lisp:467 が確かめ、直前のコマンドの成功はこのシナリオの他の対応で確かめる |
| `expected.side_effects.history.path` | ".local/share/nshell/history" | `t/integration/test-file-history.lisp:448` it "file-history-xdg-path-and-empty-load" | XDG_DATA_HOME が空・相対・未設定のとき、履歴の場所が ~/.local/share/nshell/history になることを確かめる |
| `expected.side_effects.history.contains[0]` | "T05_HISTORY_IMPORTED_OK" | `t/integration/test-file-history.lisp:491` it "file-history-legacy-import-preserves-source-and-is-idempotent" | 旧形式から取り込んだ記録を、2 回目の load-history-file が取り込み先から同じ 1 件として読むことを確かめる |
| `steps[2].contains` | "echo T05_HISTORY_IMPORTED_OK" | なし | expected.stream.contains[0] と同じ理由で対応するテストはない |

### T05-legacy-history-import-is-idempotent

`t/scenarios/T05/legacy-history-import-is-idempotent.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "echo T05_HISTORY_IMPORTED_OK" | なし | test-history.lisp:109 は history-add で入れた履歴の Ctrl-R の検索だけを確かめ、旧形式から取り込んだ記録の検索は確かめていない |
| `expected.stream.contains[1]` | "T05_IMPORT_APPEARS_ONCE" | `t/integration/test-file-history.lisp:491` it "file-history-legacy-import-preserves-source-and-is-idempotent" | 2 回の load-history-file のどちらでも記録が "legacy command" の 1 件だけであることを確かめ、取り込み先に重複が無いことを含む |
| `expected.stream.contains[2]` | "T05_SESSION_DONE" | `t/e2e/test-smoke-script.lisp:176` it "e2e-main-command-expands-documented-core-forms" | 同期用マーカー。$((...)) の語中展開・$VAR の展開と echo の出力を --command 経路で最後まで走らせて確かめる |
| `expected.exit_code` | 0 | `t/e2e/test-smoke.lisp:439` it "e2e-main-interactive-pty-smoke" | 実 PTY の nshell に exit を送り Goodbye! と終了状態 0 を確かめる。exit が直前の状態を引き継ぐことは test-smoke.lisp:467 が確かめ、直前のコマンドの成功はこのシナリオの他の対応で確かめる |
| `expected.side_effects.files[0].path` | ".nshell_history" | なし | test-file-history.lisp:491 は 2 回読み込んだ後の旧ファイルのバイト列の一致を確かめるが、セッション中にコマンドを履歴へ追記した後も旧ファイルが変わらないことは確かめていない |
| `expected.side_effects.files[0].equals` | "# nshell-history-v2 28\necho T05_HISTORY_IMPORTED_OK\n" | なし | files[0].path と同じ理由で対応するテストはない |
| `expected.side_effects.history.path` | ".local/share/nshell/history" | `t/integration/test-file-history.lisp:448` it "file-history-xdg-path-and-empty-load" | XDG_DATA_HOME が空・相対・未設定のとき、履歴の場所が ~/.local/share/nshell/history になることを確かめる |
| `expected.side_effects.history.contains[0]` | "echo T05_HISTORY_IMPORTED_OK" | `t/integration/test-file-history.lisp:491` it "file-history-legacy-import-preserves-source-and-is-idempotent" | 取り込んだ記録を取り込み先から読み直せることを確かめる |

### U02-osc-133-markers

`t/scenarios/U02/approx-U02-osc-133-markers.json` [削除]

シナリオの入口: 対話 REPL（scripts/run-scenarios.py が nshell を PTY で起動し、キー列を端末から送る → 行エディタ → Enter で提出 → 実行 → 端末への出力）。TERM=xterm-256color

| assertion | 値 | 確かめているテスト | テストの入口 | 同じ入口 | 対応 |
|---|---|---|---|---|---|
| `expected.stream.contains[0]` | "U02_COMMAND_OK" | `t/scenarios/F07/approx-osc-133-prompt.json:2` scenario "F07-approx-osc-133-prompt" expected.stream.contains[0] | 残す PTY シナリオ（同じ `scripts/run-scenarios.py` が nshell を PTY で起動しキーを送る） | はい | F07 が同じ PTY・同じ TERM で echo "$VAR" を入力し、その出力が端末に届くことを確かめている。 |
| `expected.stream.ordered_contains[0]` | "\u001b]133;A" | `t/scenarios/F07/approx-osc-133-prompt.json:2` scenario "F07-approx-osc-133-prompt" expected.stream.ordered_contains[0] | 残す PTY シナリオ（同じ `scripts/run-scenarios.py` が nshell を PTY で起動しキーを送る） | はい | F07 がプロンプトの前の ESC ]133;A を同じ順序の先頭で確かめている。 |
| `expected.stream.ordered_contains[1]` | "\u001b]133;B" | `t/scenarios/F07/approx-osc-133-prompt.json:2` scenario "F07-approx-osc-133-prompt" expected.stream.ordered_contains[1] | 残す PTY シナリオ（同じ `scripts/run-scenarios.py` が nshell を PTY で起動しキーを送る） | はい | F07 が A の後の ESC ]133;B を確かめている。 |
| `expected.stream.ordered_contains[2]` | "\u001b]133;C" | `t/scenarios/F07/approx-osc-133-prompt.json:2` scenario "F07-approx-osc-133-prompt" expected.stream.ordered_contains[2] | 残す PTY シナリオ（同じ `scripts/run-scenarios.py` が nshell を PTY で起動しキーを送る） | はい | F07 が B の後、出力の前の ESC ]133;C を確かめている。 |
| `expected.stream.ordered_contains[3]` | "\u001b]133;D;0" | `t/scenarios/F07/approx-osc-133-prompt.json:2` scenario "F07-approx-osc-133-prompt" expected.stream.ordered_contains[5] | 残す PTY シナリオ（同じ `scripts/run-scenarios.py` が nshell を PTY で起動しキーを送る） | はい | F07 が出力の後の ESC ]133;D;0 を確かめている。 |
| `expected.exit_code` | 0 | `t/scenarios/F07/approx-osc-133-prompt.json:2` scenario "F07-approx-osc-133-prompt" expected.exit_code | 残す PTY シナリオ（同じ `scripts/run-scenarios.py` が nshell を PTY で起動しキーを送る） | はい | F07 が exit と Enter で終了コード 0 を確かめている。 |
| `steps[2].contains` | "U02_COMMAND_OK" | `t/scenarios/F07/approx-osc-133-prompt.json:2` scenario "F07-approx-osc-133-prompt" steps[4].contains | 残す PTY シナリオ（同じ `scripts/run-scenarios.py` が nshell を PTY で起動しキーを送る） | はい | F07 が同じ形で出力を待つ同期を行っている。 |

### U03-tmux-screen-terminal

`t/scenarios/U03/approx-U03-tmux-screen-terminal.json` [削除 (先にテストを足す)]

| assertion | 値 | 確かめているテスト | 対応 |
|---|---|---|---|
| `expected.stream.contains[0]` | "U03_TMUX_SCREEN_OK" | なし | 対話 PTY の e2e (test-signals.lisp:4 など) は %e2e-child-environment が TERM=xterm-256color に固定して走る (`t/support/runtime.lisp:45`)。TERM=screen-256color での動作を確かめるテストはない。src で TERM の値を見るのは dumb の判定 (terminal/detection.lisp:23) と色深度の判定 (terminal/ansi.lisp:147) だけ |
| `expected.exit_code` | 0 | なし | expected.stream.contains[0] と同じ理由で対応するテストはない |
| `steps[2].contains` | "U03_TMUX_SCREEN_OK" | なし | expected.stream.contains[0] と同じ理由で対応するテストはない |
