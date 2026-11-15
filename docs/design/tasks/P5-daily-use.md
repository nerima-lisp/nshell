# P5 日常使いの仕上げ

規模: 大。参照: proposal/08、ux/U4・U8。P5 以降のリリースは v0.9.x。

## P5-1 データを失わない

- [ ] 履歴の破損回復: 読めない行は飛ばし、壊れた元のファイルを `<file>.corrupt-<n>` へ退避する
- [ ] 履歴の件数上限は 10 万件で、`set` で変えられる。超えた古い分は `<file>.1` へ移す (消さない)
- [ ] schema_version と自動移行。schema_version を持たせるのは、nshell が生成する状態 (履歴・trust DB・出力ストア) だけ

## P5-2 どこでも動く

- [ ] 端末・tmux・screen・ssh・Emacs (shell-mode / vterm)・VS Code / JetBrains (-ilc) の確認表を docs に置き、リリースごとに埋める。扱うのは CI で埋められる行だけ
- [ ] 変わったファイル名 (空白・改行・先頭の -・非 UTF-8) のテスト。非 UTF-8 のファイル名のテストは Linux だけで動かす
- [ ] 大きな入力 (履歴 10 万件・数万ファイル・長い行) の遅延テスト

## P5-3 テストを強くする

- [ ] パーサと S式リーダーの fuzz を GitHub Actions の cron で毎日。入力は P2-6 で残した fuzz の入力 (`scripts/measure-nfr-07-09.py` の `lisp_fuzz_source`) を使う
- [ ] POSIX と同じと言っている展開を bash と比べる差分テスト。bash は nixpkgs のものを使う
- [ ] soak (台本どおりのキー入力でメモリと遅延を記録)。ローカルで 6 時間 × 4 回を連結し、履歴・出力ストア・RSS の推移を次の回へ引き継ぐ
- [ ] 性能の予算 6 項目 (08) を、P0-7 の v0.7.0 の基準に対するラチェット (悪化を許さない上限) としてローカルで守る。絶対値の目標は決めない

## P5-4 迷わない

- [ ] nshell init / nshell import (bash・zsh・fish の履歴と alias → abbr)。予約語 `init`・`import` を登録する
- [ ] F1 / Alt-H のヘルプパネル、help keys
- [ ] nshell doctor (proposal/06 G の規則)。予約語 `doctor` を登録する。プロバイダの点検は P4-2 の `provider-check` を使う
- [ ] 日本語のメッセージ (LANG=ja)。メッセージ ID をキーにしたデータ表で持ち、P0-3 の英語と日本語の説明を流用する

## P5-5 場所に合わせる・使い回す

- [ ] プロジェクト設定 `.nshell.lisp` と `nshell trust` (予約語 `trust` を登録する)。trust のハッシュは cl-crypto-kit の SHA-256 を使う。安全モード (`nshell.application:*safe-mode-p*`、P0-5) では読まない
- [ ] Nix との連携。提案だけを行い、`nix develop` を自分で実行しない
- [ ] 出力ストア `(out)`・`(view)`・`clip`・Alt-T のファイル挿入。`(view)` は P3-5 のレコードの表の部品を使うページャとして作る
- [ ] bash からの書き換え
- [ ] 色覚に配慮したテーマ (ui :plain をスクリーンリーダーで確かめるのは人の作業なので、ここには含めない)

## P5-6 配布

- [ ] SBOM と GitHub の artifact attestation
- [ ] SBOM は CycloneDX 形式で、固定した nixpkgs の sbomnix で作る
- [ ] attestation の action は SHA で固定し、`id-token` と `attestations` の書き込み権限を与える

## P5-7 ユーザー規則の制限

- [ ] rules.pl を読み込む (P1-5 の別の rulebase に入れ、結果は confirm までに抑える)。安全モード (`nshell.application:*safe-mode-p*`、P0-5) では読まない
- [ ] rules.pl から外部コマンドは呼べない。外部述語 (foreign predicate) は許可リストのものだけ
- [ ] 推論数と時間の上限をかける

## P5-8 初回起動の 1 行ヒント

- [ ] 初回起動のときに 1 行のヒントを出す

## P5-9 AI 応答の整形と端末の機能

- [ ] AI の応答の整形
- [ ] OSC 8 のリンク
- [ ] 同期描画
- [ ] 対応端末での画像
