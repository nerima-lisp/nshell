# P0 土台 — 壊れても戻れる、AI が迷わない状態にする

規模: 小。目的: 以降のすべての作業の足場。P0 の間は利用者から見た挙動を変えない。

## P0-1 AGENTS.md / CLAUDE.md を仕上げる

- [ ] ルートの `AGENTS.md` と `CLAUDE.md` (この計画と一緒に追加済み) を読み、実際のコマンドで確認して直す
- [ ] `nix develop` 内の `test` / `weave` / `cov` と、Nix なしの手順の両方が通ることを確認

受け入れ条件: 新しいセッションの Claude Code が AGENTS.md だけを読んで、ビルドと全テストを実行できる。

## P0-2 test-fast

- [ ] `scripts/test-fast.lisp`: `t/unit/` だけを読み込んで実行する (PTY・e2e・perf・シナリオは除く)
- [ ] `nix develop` に `test-fast` の alias を追加。Nix なしでも `sbcl --script scripts/test-fast.lisp` で動く
- [ ] 実行時間を README か AGENTS.md に書く

受け入れ条件: 一般的な開発機で 30 秒以内。失敗したテストがあれば終了コード 1。

参照: proposal/03 B、proposal/08「テストの組み立て」

## P0-3 エラーコードの一覧

- [ ] `data/application/error-codes-data.lisp` に全コードを定義 (名前・既定の終了コード・英語と日本語の短い説明・直し方の例)
- [ ] 対象: proposal/02 と ux/U6 の実行系 (E_COMMAND_NOT_FOUND, E_PERMISSION, E_TIMEOUT, E_INTERRUPTED, E_NEEDS_APPROVAL, E_BLOCKED_BY_POLICY, E_WAITING_FOR_INPUT, E_INTERACTIVE_PROGRAM) と language/L6 の言語系 (E_PARSE, E_UNSUPPORTED_SYNTAX, E_ARG_TYPE, E_VALUE_POSITION, E_NO_MATCH, E_REDIRECT_TARGET, E_LISP_ERROR, E_COMMAND_FAILED)
- [ ] condition に `error-code` スロットを足す (表示はまだ変えない)
- [ ] 一覧から docs/src/reference/error-codes.md を生成するテスト (ずれたら失敗)

受け入れ条件: すべてのコードが 1 か所に定義され、ドキュメントと一致することがテストで保証される。

## P0-4 想定外のエラーからの復帰とクラッシュログ

- [ ] REPL の 1 周を handler で囲み、捕まえたエラーのバックトレースを `$XDG_STATE_HOME/nshell/crash/<時刻>.log` に書いてプロンプトへ戻る
- [ ] 同じ場所で 3 回続いたら `--safe` 相当で再起動するか尋ねる
- [ ] storage-condition とスタック溢れも同じ経路で処理する

受け入れ条件: テスト用の builtin でわざとエラーを起こしても端末が raw mode のまま残らず、履歴が失われない (PTY テスト)。

参照: proposal/08「端末を壊さない・固まらない」

## P0-5 --safe

- [ ] `nshell --safe`: init.lisp・プロジェクト設定・ユーザー規則・AI を読まずに起動
- [ ] プロンプトに安全モードの印

受け入れ条件: 壊れた init.lisp (構文エラー・無限ループ・存在しない関数の呼び出し) でも `--safe` で起動できる。

## P0-6 nshell bug-report

- [ ] 版・OS・端末 (TERM, COLORTERM, 幅)・SBCL の版・秘匿化した設定・直近のクラッシュログを集め、issue の下書きを標準出力か一時ファイルに出す
- [ ] 送信はしない。redaction を通すテストを書く

受け入れ条件: 出力に HOME のパス・環境変数の値・トークンらしき文字列が含まれない。
