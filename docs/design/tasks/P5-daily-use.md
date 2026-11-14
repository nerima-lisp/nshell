# P5 日常使いの仕上げ

規模: 大。参照: proposal/08、ux/U4・U8。

## P5-1 データを失わない

- [ ] 履歴の破損回復 (読めない行は飛ばし、元を退避)、件数上限とローテーション
- [ ] 履歴・設定・出力ストアの schema_version と自動移行

## P5-2 どこでも動く

- [ ] 端末・tmux・screen・ssh・Emacs (shell-mode / vterm)・VS Code / JetBrains (-ilc) の確認表を docs に置き、リリースごとに埋める
- [ ] 変わったファイル名 (空白・改行・先頭の -・非 UTF-8) のテスト
- [ ] 大きな入力 (履歴 10 万件・数万ファイル・長い行) の遅延テスト

## P5-3 テストを強くする

- [ ] パーサと S式リーダーの fuzz を CI で毎日
- [ ] POSIX と同じと言っている展開を bash と比べる差分テスト
- [ ] 24 時間 soak (台本どおりのキー入力でメモリと遅延を記録)
- [ ] 性能の予算 6 項目 (08) を測って目標値を決め、CI で守る

## P5-4 迷わない

- [ ] nshell init / nshell import (bash・zsh・fish の履歴と alias → abbr)
- [ ] F1 / Alt-H のヘルプパネル、help keys
- [ ] nshell doctor (proposal/06 G の規則)
- [ ] 日本語のメッセージ (LANG=ja)

## P5-5 場所に合わせる・使い回す

- [ ] プロジェクト設定 `.nshell.lisp` と `nshell trust`
- [ ] Nix との統合
- [ ] 出力ストア `(out)`・`(view)`・`clip`・Alt-T のファイル挿入
- [ ] bash からの書き換え
- [ ] 色覚に配慮したテーマ・ui :plain をスクリーンリーダーで確認

## P5-6 配布

- [ ] SBOM と GitHub の artifact attestation
