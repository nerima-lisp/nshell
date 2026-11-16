# P0 土台 — 壊れても戻れる、AI が迷わない状態にする

規模: 小。目的: 以降のすべての作業の足場。P0 の間は利用者から見た挙動を変えない。例外は不具合の修正である P0-9 (Alt-Enter) と P0-10 (abbreviation の正規表現) だけ。

## P0-1 AGENTS.md / CLAUDE.md を仕上げる

- [x] ルートの `AGENTS.md` と `CLAUDE.md` (この計画と一緒に追加済み) を読み、実際のコマンドで確認して直す
- [x] 層の向きをコードの規則 `domain ← infrastructure ← application ← presentation` (`t/unit/test-static-checks.lisp` の層の規則) に合わせる
- [x] エージェントが使うコマンドは `nix develop -c sbcl --script …` と書く。`test` / `weave` / `cov` の alias は対話シェルでしか動かないので、人向けとして書く
- [x] テストの隔離に使う環境変数として HOME・XDG_CONFIG_HOME・XDG_DATA_HOME・XDG_STATE_HOME・XDG_CACHE_HOME の 5 つと `NSHELL_AI_COMMAND=/nonexistent` を書く。PTY テストに `NSHELL_TEST_PTY=1` が要ることも書く。件数のように時間で変わる数は書かない
- [x] Nix なしの手順を `scripts/bootstrap-without-nix.sh` にまとめる (kit の取得、`nix/patches/` のパッチの適用、補助プログラムのビルド)。AGENTS.md はこのスクリプトを指すだけにする
- [x] ubuntu の CI ジョブ `no-nix` でこのスクリプトを流し、`run-tests.lisp` まで通す

受け入れ条件: 新しい Claude Code のセッションに AGENTS.md だけを渡し、ほかの文書を読まずにビルドと全テストを実行できる。

## P0-2 test-fast

- [x] `scripts/test-fast.lisp`: `t/unit/` と `main-test`・静的チェックだけを読み込んで実行する (PTY・e2e・perf・シナリオは除く)
- [x] test-fast は `nshell/test-unit` システムとして切り出し、`nshell/test` がそれに依存する形にする
- [x] `nix develop` に `test-fast` の alias を追加。Nix なしでも `sbcl --script scripts/test-fast.lisp` で動く
- [x] 目標の 30 秒と計測方法を `AGENTS.md` に書く。キャッシュなしとキャッシュ済みの実測値と計測条件はコミットメッセージに残す

受け入れ条件: 一般的な開発機で 30 秒以内。30 秒はキャッシュ済みでの時間で、`NSHELL_ASDF_OUTPUT_DIR` を `$XDG_CACHE_HOME` の下に固定して測る。超えたら、測ったうえで重いテストに `:slow` タグを付けて外す。失敗したテストがあれば終了コード 1。

参照: proposal/03 B、proposal/08「テストの組み立て」

## P0-3 エラーコードの一覧

- [x] `data/domain/error-codes-data.lisp` に全コードを定義 (名前・既定の終了コード・英語と日本語の短い説明・直し方の例)。domain 層と infrastructure 層からも参照できるように、data/application ではなく data/domain に置く
- [x] 対象: proposal/02 と ux/U6 の実行系 (E_COMMAND_NOT_FOUND, E_PERMISSION, E_TIMEOUT, E_INTERRUPTED, E_NEEDS_APPROVAL, E_BLOCKED_BY_POLICY, E_WAITING_FOR_INPUT, E_INTERACTIVE_PROGRAM) と language/L6 の言語系 (E_PARSE, E_UNSUPPORTED_SYNTAX, E_ARG_TYPE, E_VALUE_POSITION, E_NO_MATCH, E_REDIRECT_TARGET, E_LISP_ERROR, E_COMMAND_FAILED)、E_INTERNAL・E_NOT_IMPLEMENTED・E_PROTOCOL、警告用の W_*
- [x] 既定の終了コードは次の表に従う

| 終了コード | エラーコード |
|---|---|
| 2 | E_PARSE, E_UNSUPPORTED_SYNTAX, E_PROTOCOL |
| 1 | E_ARG_TYPE, E_VALUE_POSITION, E_NO_MATCH, E_REDIRECT_TARGET, E_LISP_ERROR, E_NOT_IMPLEMENTED |
| 子の終了コード | E_COMMAND_FAILED |
| 127 | E_COMMAND_NOT_FOUND |
| 126 | E_PERMISSION |
| 124 | E_TIMEOUT |
| 130 | E_INTERRUPTED |
| 3 | E_NEEDS_APPROVAL |
| 4 | E_BLOCKED_BY_POLICY |
| 5 | E_WAITING_FOR_INPUT |
| 6 | E_INTERACTIVE_PROGRAM |
| 70 | E_INTERNAL |

- [x] condition の mixin に `error-code` スロットを足す (表示はまだ変えない)
- [x] 一覧から docs/src/reference/error-codes.md を生成するテスト (ずれたら失敗)

受け入れ条件: すべてのコードが 1 か所に定義され、ドキュメントと一致することがテストで保証される。

## P0-4 想定外のエラーからの復帰とクラッシュログ

- [x] REPL の 1 周を `handler-bind` で囲み、捕まえたエラーのバックトレースを `$XDG_STATE_HOME/nshell/crash/<時刻>.log` に書いてプロンプトへ戻る。XDG_STATE_HOME が未設定なら `~/.local/state/nshell/crash/`
- [x] クラッシュログのディレクトリは 0700、ファイルは 0600。秘匿化を通し、HOME を `~` に置き換える。バッチでも書く
- [x] 「同じ場所」は condition の型と最も内側の nshell のフレームで判定する。同じ場所で 3 回続いたら、実行中のジョブを一覧表示してから `--safe` で re-exec するか尋ねる
- [x] storage-condition とスタック溢れも同じ経路で処理する

受け入れ条件: テスト用の builtin でわざとエラーを起こしても端末が raw mode のまま残らず、履歴が失われない (PTY テスト)。

参照: proposal/08「端末を壊さない・固まらない」

## P0-5 --safe

- [x] `nshell --safe`: init.lisp・conf.d・`.nshell.lisp`・rules.pl・AI・functions の自動読み込み・NSHELL_PROMPT を読まずに起動する。履歴は読む
- [x] `NSHELL_SAFE=1` でも同じになる。`--config` との併用は使い方のエラー
- [x] プロンプトに安全モードの印。利用者の書式の外に、固定で `[safe] ` と出す

受け入れ条件: 壊れた init.lisp (構文エラー・無限ループ・存在しない関数の呼び出し) でも `--safe` で起動できる。

## P0-6 nshell bug-report

- [x] サブコマンドは予約語を優先する仕組みを作る。同名のスクリプトは `nshell ./doctor` か `nshell -- doctor` で実行する。予約語は、そのサブコマンドを実装するタスクがそのつど登録する (bug-report・explain・migrate・doctor・init・import・trust)
- [x] 版・OS・端末 (TERM, COLORTERM, 幅)・SBCL の版・秘匿化した設定・直近のクラッシュログを集め、issue の下書きを標準出力に出す
- [x] 値を出してよい環境変数は TERM・COLORTERM・LANG・LC_* だけ。設定ファイルは、有無・サイズ・sha256 と、設定済みの NSHELL_* の名前だけを出す
- [x] 送信はしない。redaction を通すテストを書く

受け入れ条件: 出力に HOME のパス・トークンらしき文字列が含まれず、環境変数の値は TERM・COLORTERM・LANG・LC_* のもの以外を含まない。

## P0-7 性能の基準と計測

- [x] v0.7.0 の性能の基準と、それと比べる計測の仕組みを作る。項目は 6 つ: warm の起動・cold の起動・キー入力の遅延・Tab 補完・プロンプトの表示・メモリ
- [x] `bench/` の既存の計測はここへまとめる
- [x] 同じバイナリ同士でも測り、ばらつきを記録する

受け入れ条件: 以降のタスクのうち、キー入力・起動・描画・履歴に触れるものは、この基準と比べて確かめられる。

## P0-8 性能の負債を直す

- [x] キーごとの `snapshot.json` の書き込み
- [x] 伸びていくコマンド名ごとに PATH の全ディレクトリを `stat` している処理
- [x] Ctrl-R と履歴の移動で、履歴ファイル全体を読み直している処理
- [x] 未マージの NFR-05 の修正 (`44ba2e6c`・`7db22062`・`6405f871`・`18303666`) を取り込む

P0-8 以降のすべてのタスクで守る規則:

- キー入力の経路でファイル I/O とプロセス起動をしない
- 知識ベースへの問い合わせは入力の区間をキーにしてキャッシュし、推論数と時間の上限を付ける
- 文法と組み込みの規則はビルド時にコンパイルする
- プレビューと fuzzy 検索は非同期で、取り消せるようにする

## P0-9 Alt-Enter で改行を入れる

- [x] Alt-Enter で入力行が実行されてしまう不具合を直し、改行を入れる動作にする。読み取り側に `:alt-enter` を足す

受け入れ条件: Alt-Enter で入力が実行されない。修正案を入力欄へ適用する動作は P3-3 で足す。

## P0-10 abbreviation の正規表現

- [ ] 正規表現の abbreviation がトークン全体に一致するかを `full-match-p` で判定する。いまは最初に見つかった一致だけを見るので、`a|ab` が `ab` に一致しない
- [ ] 正規表現のコンパイル結果をキャッシュする

受け入れ条件: `a|ab` の abbreviation が `ab` で展開される。
