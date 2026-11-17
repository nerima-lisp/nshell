# P2 言語の整理と削減

規模: 大。目的: 言語仕様 v0.8 (language/L0〜L7) を実装し、二重実装と計測の層を外す。P1 の golden / spec テストが安全網。P2 の完了で v0.8.0 を出す。

language/L7.1 の各行は、v0.8 で新しい挙動に切り替えるものと、v0.8 では旧挙動のまま書き換え案つきの警告を出して次のバージョン (v0.9.0) で切り替えるものに分かれる。どちらに入るかは language/L7 の表に従う。

## P2-1 読み取り (L1)

- [ ] Lisp の部分の記号を大文字に揃える。コマンドの語は書いたまま。REPL の値の表示は `*print-case* :downcase`
- [ ] 字句の読み方は名前の分類に依存させない。`|…|`・`#`・`,` は Lisp の部分でも語頭でだけ特別な意味を持つ
- [ ] 語の途中の `,` `|` `#` は文字 (`(echo a,b)` と `(echo a|b)` は v0.8 では旧挙動のまま警告し、v0.9.0 で切り替える。L7.1)。`$` は英字・_・{ が続くときだけ変数
- [ ] 文字列のエスケープ \n \t \r \e \0 \\ \" \u{…}
- [ ] Lisp の部分の `<` `>` を比較関数として読む (`(function <)`・`#'<`)
- [ ] 完結した S式は 1 行に複数並べてよい。E_PARSE にするのは、S式の後ろに bare-line が続く場合 (`(echo hi) | tr a-z A-Z` など) だけ
- [ ] スクリプトは全体を読んでから実行 (L6.1)
- [ ] エラーは 1 回だけ、原因の開始位置つきで出す (L6.2)。新しい見た目の表示は P3-3

## P2-2 名前解決 (L2)

- [ ] 2.1 の 9 段の順序を実装し、PATH を見るのは最後の段だけにする
- [ ] 衝突表をデータとして持つ。コマンド側は `sort find sleep time open`。`join` と `split` は CL にないので表に入れない
- [ ] explain に規則番号を出す
- [ ] 意味が変わる入力には v0.8 の間だけ警告。`,(find …)` が E_VALUE_POSITION に変わる件は v0.8 では警告にとどめる

## P2-3 コマンド形式と値 (L3・L4)

- [ ] 引数の書き方の表 (L3.1) と値の変換表 (L3.2)。`(FORM)` 置換と `$(…)`。defun の既知の不具合 2 つ (どちらも v0.7.0 からある) もここで直す。BUG-6: defun をパイプラインの段にすると、本体で動かした外部コマンドの出力が消える (`eval '(defun f () (sh -c "echo x"))'; f | cat` が何も出力しない)。このため F3 は、`t/e2e/test-machine-json-golden.lisp` の it "keeps a function stage's output from before its exec in order" の本体から exec の前の `sh -c 'echo x'` を外し、期待する出力から `X` の行を外した。BUG-6 を直したら、defun の本体の exec の前に `(sh -c "echo x")` を戻し、期待する出力を `A`・`X`・`B`・`after` の 4 行に戻す。BUG-7: `$(…)` の中のパイプラインでは defun が見つからず、`$(f | cat)` が `f: command not found` になる (`$(f)` は動く)。このため F3 は、同じファイルの it "keeps a function stage's output from before its exec in a command substitution" (`echo $(f | cat); echo after` が `a b` と `after` を出す) を削除した。BUG-7 を直したら、f を defun で定義してこの it を戻す
- [ ] `:kw` をコマンドの引数にしたときは、v0.8 から `":kw"` として渡し、警告を出す
- [ ] リダイレクトの対象に `,EXPR`、`2>&1` などの複製。L3.4 の表にない `>|`・`<&`・`0<`・`1>` も残す
- [ ] `(& FORM)`・`with-env`
- [ ] 位置の規則 (L4.1): 値の位置のコマンドは E_VALUE_POSITION。`and`/`or`/`not` は常に条件として評価
- [ ] CL のマクロの中では、暗黙の本体を文の位置、引数を値の位置として扱う。コードウォーカーか lowering で実装する
- [ ] capture / capture-lines / capture-json / status / run / glob / files / str
- [ ] 一致しない glob は、v0.8 では警告を出して語のまま渡す (次のバージョンで E_NO_MATCH)。変えるのはコマンド引数の展開だけで、補完が使う `expand-glob` には触れない
- [ ] `$name` を Lisp の部分でも使えるように (L4.3)。Lisp の束縛なら大文字にして照合し、シェル変数と環境変数は書いたまま照合する。`$status` は整数
- [ ] 値を返す builtin (L4.4): jobs history dirs functions abbr type complete pwd
- [ ] defcmd (define-shell-function は別名)
- [ ] L2 2.2 の名前は defun でも再定義を拒否する。新しく入る defcmd では v0.8 から E_PARSE。既存の書き方 (defun・define-shell-function・alias・abbr) では v0.8 は警告と `nshell migrate` で知らせ、次のバージョンで E_PARSE にする
- [ ] ある名前が defun と defcmd または alias の両方で定義されたら、後の定義を採って警告する。abbr はスクリプトでは展開しない
- [ ] `out` `view` `clip` `?-` は、P4・P5 で実装するまで E_NOT_IMPLEMENTED を返す
- [ ] レコードと JSON の規則 (L4.6)、where の比較演算子 (L4.7)
- [ ] スクリプトではトップレベルの値を表示しない (L4.8)

## P2-4 bare-line (L5)

- [ ] bare-line の制御構文 (if・for・while・switch・function・begin)、here-doc (`<<`・`<<-`)、`!`、`not cmd; and cmd2` の形を v0.8 で削除する。実行前に E_UNSUPPORTED_SYNTAX で入力全体を拒否し、L5.3 の表にある同じ意味の S式を示す
- [ ] 語の中の ( … ) を S式の置換に
- [ ] `$xs[2]` の添字
- [ ] bare-line の `,expr` は L5.1 の文法にないので、v0.8 では警告し、次のバージョンで削る

## P2-5 移行

- [ ] L7.2 の警告をすべて出す。警告には書き換え案を含める。`--json` では応答の `warnings[]` に入れる
- [ ] 同じ箇所への警告は 1 セッションに 1 回だけ出す
- [ ] `nshell migrate FILE`: 該当箇所と書き換え案の一覧 (書き換えはしない)。予約語 `migrate` を登録する

受け入れ条件 (P2-1〜P2-5 共通): `t/spec/` の v0.8 の期待値 (`it`) がすべて通り、次のバージョンの期待値は `it-fails` のまま残る。それ以外の golden は変わらない (変わったものは理由を PR に書く)。

## P2-6 削除

- [ ] contracts 層 (src/application/contracts, src/presentation/contracts) を unit テストに吸収して削除
- [ ] NFR 計測・競合ベンチのスクリプトのうち、P0-7 の計測で置き換えたものだけを削除する。fuzz の入力 (`scripts/measure-nfr-07-09.py` の `lisp_fuzz_source`) は P5-3 のために残す
- [x] fish 形式のビルトイン 10 個 (and or not break continue function count contains seq math)、prevd / nextd、pipeline-graph
- [x] slurp / barf、マウス、Ctrl-X 再実行、Alt-C / Alt-L / Alt-U / Alt-T の既定割り当て
- [ ] シナリオコーパスを、30〜40 本を目安に (基準に当たる 41 本) 絞る。batch のものは golden へ移し、それ以外は 1 本ずつ削除の理由を記録する。CI が ID を指定している P12・L02・T06・J05・Q03・Q07・Q08 は残す。1 本ずつの判定は [P1-7c-scenario-corpus.md](P1-7c-scenario-corpus.md) に従う。Q05 の NFS VM 専用ジョブと試行は、2026-11-15 の別々の試行で delayed glob の 3 回目と baseline glob の 1 回目が失敗し、nshell の変更ごとに CI が不安定になっていたため前倒しで外した (`e0c76568`)。`Q05-git-probe-timeout-does-not-block-input` シナリオは、前倒しで外したものに含まれない
  - [ ] [P1-7c-scenario-corpus.md](P1-7c-scenario-corpus.md) で [削除 (先にテストを足す)] にしたシナリオは、一覧の「削除の前に」に書いたテストを足し、そのテストと同じコミットで消す。系統ごとに次の小項目で進める
  - [ ] `--command` とスクリプトの e2e (52 本): A03-login-shell-command、A06-login-environment、A07-quiet-login-command、A10-exec-replaces-shell、B06-approx-shell-c-command-contract、B09-batch-command-uses-nshell-builtins、B09-command-stdio-and-status、B09-empty-shell-command、B09-shell-command-argv、C01-batch-command、C01-batch-stdin、C03-path-search-and-absolute-path、C04-missing-command-suggestion-and-status、C05-last-exit-status-is-visible、C06-pipeline-streams-all-stages、C07-redirection-family、C08-here-doc-and-here-string、C09-background-command-returns、C10-short-circuit-followed-by-sequence、C11-temporary-command-environment、C14-tilde-and-brace-expansion、C16-approx-process-substitution-input、C17-approx-large-binary-and-invalid-utf8-output、K07-one-line-source-diagnostic、K08-macro-expansion-error-location、L07-theme-can-be-selected、M01-cd-dash、M02-logical-pwd-and-pwd-variable、M05-pushd-popd-stack-round-trip、N01-session-variable、N02-export-reaches-child-process、N03-colon-separated-path-list、N04-unset-removes-variable、N05-approx-lexical-let-scope、N07-status-and-pipeline-status、O02-command-island-evaluation、O03-let-and-set、O04-control-forms、O05-nested-command-definitions、O06-macro-expansion、O07-conditional-and-handler-case、O08-structured-pipeline、O09-json-tsv-lines-conversion、O10-regex-and-string-library、O11-native-arithmetic、O12-comments、O13-script-shebang-and-source、O14-function-directory-autoload、O15-asdf-library-load、O16-preserve-case、O18-alias-eval-and-string-execution、T03-help-output。golden へ移す K06・P07・P10・Q01 のスクリプトの入口を確かめる e2e も、この小項目で足す
  - [ ] reducer と描画 (67 本): WP-R10-whitespace-keeps-repl-alive、A08-ctrl-d-exits、A08-exit-warns-about-job、A13-config-error-keeps-prompt、B07-B08-interactive-callers、C01-pty-paste、C12-approx-privileged-command-dispatch、C18-approx-sigpipe-is-quiet、F10-unicode-grapheme-cursor-edit、F11-16-color-sgr、F11-256-color-sgr、F11-no-color-sgr、G01-approx-emacs-case-transform、G01-approx-emacs-transpose、G01-approx-emacs-word-delete、G01-case-conversion、G01-char-transpose、G01-word-forward-motion、G01-word-motion-deletion、G01-word-transpose、G02-approx-vi-mode-editing、G02-delete-a-word、G02-delete-inner-word、G02-goto-end、G02-undo-find-replace-repeat、G02-vi-e-nfd-grapheme-boundary、G02-yank-put-inner-word、G03-undo-redo、G04-approx-kill-ring-yank、G04-kill-ring-yank-pop、G05-approx-multiline-buffer-navigation、G06-nested-matching-delimiters、WP-E03-blank-continuation-keeps-shell-alive、G08-structural-editing、G09-approx-balanced-parentheses-before-enter、G11-clear-screen-keeps-prompt、G11-clear-screen、G12-approx-grapheme-cursor-boundary、G12-grapheme-boundary、G13-ctrl-y-yank、G13-ctrl-y-yanks-killed-text、K01-command-existence-colors、K02-existing-path-is-underlined、K03-redirection-target-is-not-an-error、K04-unbalanced-parenthesis-diagnostic、K05-string-highlighting、L01-left-and-right-prompt、L02-slow-git-status-does-not-block-input、L03-status-duration-jobs-prompt-segments、L04-approx-transient-prompt-keeps-current-prompt、L05-approx-custom-prompt-format、L06-approx-narrow-terminal-redraw、O07-interactive-command-failed-restart、P01-xdg-init-file、P02-conf-d-order、P03-function-directory、P04-abbreviation-expansion、P06-key-binding、P08-prompt-format、P11-continue-after-config-error、Q02-bounded-recursion-recovery、Q04-cancel-completion、Q05-git-probe-timeout-does-not-block-input、Q08-normal-key-handler-remains-usable、T05-legacy-history-load、T05-legacy-history-import-is-idempotent、U03-tmux-screen-terminal。C01-pty-paste は、残す F08-large-bracketed-paste のシナリオに `screen.contains` を足してから消す
  - [ ] 履歴 (27 本): H01-history-persists-after-exit、H02-approx-seeded-session-history、H02-live-history-shared-between-sessions、H03-duplicate-entry-suppression、H04-leading-space-is-not-saved、H05-private-mode-does-not-save-history、H06-multiline-reverse-search、H07-approx-history-cwd-and-exit-filters、H08-delete-history-entry、H09-up-arrow-prefix-search、H10-token-history-search、H11-last-argument-insertion、H12-history-expansion、H13-malformed-history-recovers、H14-approx-history-timestamp-metadata、H14-history-persists-timestamp-metadata、H14-history-timestamps-display-utc、H15-history-ignores-xdg-state-home、H15-history-uses-xdg-data-home、I01-history-autosuggestion、I02-completion-autosuggestion、I03-partial-word-suggestion-acceptance、I05-cwd-ranked-history-suggestion、I06-enter-does-not-accept-suggestion、I06-enter-typed-text-only、I06-paste-enter-typed-text-only、I07-suggestion-keystrokes-remain-responsive
  - [ ] 補完 (22 本): J01-command-name、J02-symlink-target-kind-cache-invalidation、J02-bare-file-completion、J02-filename-insertion-pty、J02-filename-variants、J03-cd-and-cdpath、J04-home-and-variable-path、J06-catalog-subcommands、J07-ssh-hostname、J08-make-target、J09-approx-kill-completion、J10-environment-variable-name、J11-wrapper-command-completion、J12-large-directory-completion、J12-twenty-thousand-entry-directory、J14-case-and-fuzzy-match、J14-fuzzy-match-insertion-pty、J15-sexp-context、J16-approx-user-defined-completion、J17-approx-unknown-command-learning-responsiveness、J17-ctrl-c-immediate-next-command、J18-approx-completion-candidate-preview
  - [ ] ジョブ (6 本): D12-ctrl-c-stops-foreground-child、E02-bg-resumes-stopped-descendant、E02-fg-bg-and-jobs、E06-completion-notification-and-removal、E07-pipeline-is-one-stopped-job、E09-script-job-state-updates。テストを書く前に、PTY なしでジョブ制御が動くかを確かめる。`%run-terminal-command` で止めた子がジョブとして記録され、`fg`・`bg` で再開できることを、端末を持たないプロセスで 1 回流して確かめる (`src/application/manage-job.lisp` の 33〜52 行は端末の受け渡しを `ignore-errors` で包んでいる)。動かなければ、そのシナリオは消さずに残す本数の見直しに戻す
  - [ ] AI (8 本): S01-ask-mode-cancel、S02-proposal-awaits-approval、S03-explains-last-failure、S04-approves-agent-steps-individually、S05-noninteractive-ai-status、S06-classifies-and-gates-sexp-proposals、S07-shell-without-claude、S07-cancel-resumes-after-new-request
  - [ ] 静的な照合と flake (2 本): T01-platform-support-matches-flake、T02-etc-shells-guidance。この 2 本の確認を `t/unit/test-static-checks.lisp` に移し、`flake.nix` の 817〜829 行の `sourceInclude` (チェック用のソース) に `./flake.nix` と `./docs/src/getting-started.md` を足す。T01 はこの 2 つを読み比べるので、足さないと CI のサンドボックスでファイルが見つからない。T02 を読んでいる `scripts/test-run-scenarios.py` の 213 行も直す
  - [ ] golden の追加: P1-7c で [golden へ移す] にした 13 本 (A12-no-config-skips-startup、B02-approx-remote-shell-command-contract、C02-quoted-unicode-arguments、C13-glob-patterns-and-unmatched-path、C15-approx-captured-command-value、E03-kill-percent-one、E04-disown-removes-job、E05-wait-collects-background-status、J02-same-second-directory-cache-invalidation、K06-sexp-and-command-island-evaluation、P07-theme-selection、P10-completion-definition、Q01-no-debug-dump) と、J03・J04 の「削除の前に」に書いた golden のケース 2 本 (`t/golden/J03-cd-and-cdpath.json`・`t/golden/J04-home-and-variable-path.json`) を `t/golden/` に置き、いまの 4 本 (F3 で移した C06-builtin-reads-stdin を含む) と合わせて 19 本にする。Linux (x86_64-linux) の CI で 19 本が一致することを確かめてから、元のシナリオを消す
  - [ ] batch と source のシナリオがなくなると、`scripts/run-scenarios.py` の 363 行の検査で選択が空になり、`--mode batch` と `--mode source` の実行が失敗する。そのため、`.github/workflows/scenarios.yml` の 80〜84 行の source の実行と、`flake.nix` の 1204〜1205 行の batch と source の実行を外す。消したシナリオの ID を `t/scenarios/expected-scenarios.json` から外す。この 2 つの実行は、最後の batch のシナリオと最後の source のシナリオを消すコミットで、それぞれ同時に外す。先に外すと残りのシナリオが流れなくなり、後に外すとそのコミットの CI が空の選択で失敗する
  - [ ] 後始末: batch の実行を外したあとに残る名前を直す。`.github/workflows/scenarios.yml` の 163 行と 171 行の step の名前、`flake.nix` 1186 行の `checks.scenarios-batch`、`t/scenarios/README.md` 343〜347 行の `scenarios-batch` と `--mode batch` の説明
- [ ] cl-dataflow-kit・cl-boundary-kit への依存を外す (どちらもコードの変更が要る)。cl-boundary-kit をイメージから消すため、cl-concurrent-kit と cl-resilience-kit からも外す。この 2 つでの用途は時計だけなので、cl-host-kit の時計に置き換える

受け入れ条件: 全テストが通り、inventory/I1〜I9 の「削除候補」がすべて消えている。
