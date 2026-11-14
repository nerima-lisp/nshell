# 人間の UX ④ はじめてと、迷ったとき

説明書を読まなくても始められて、困ったらその場で答えが出る状態を目指します。

*初回だけの 1 行 (2 回目以降は出さない)*

```
nshell 0.8 · ? で AI · F1 ヘルプ · doctor
~/src/nshell main ❯
```

*F1: カーソル位置のコマンドの説明 (知識ベースから)*

```
~/src/nshell main ❯ tar -x█
╭ tar · F1
│ -x  extract files from an archive
│ -f  archive file  (よく一緒に使う)
│ -z  gzip        exclusive with -j -J
╰ Esc 閉じる · Tab で挿入
```

*nshell doctor (06-G の規則で点検)*

```
~/src/nshell main ❯ nshell doctor
  ✓ init.lisp を読み込み (0.03s)
  ✓ 履歴 12,408 件 · 書き込み可
  ! abbr gs が /usr/bin/gs を隠しています
     abbr --erase gs  か  abbr gst … に変更
  ! Alt-← が端末で届いていません (Option を Meta に)
  ✓ AI: claude-code · ログイン済み · ollama 未起動
  2 件の注意 · --json でも出力
```

## 最初の 10 分と、迷ったとき

- 設定ファイルなしで完成した状態にする。nshell init はコメントつきの init.lisp を生成するだけ。
- bash / zsh / fish の履歴と alias は nshell import で取り込み (alias は abbr に変換)。起動時には聞かない。
- F1 はカーソル位置のコマンドやフラグの説明、help はカテゴリ別の索引、help keys はキー一覧。
- doctor は設定の矛盾・端末のキー・AI の接続を点検し、直し方まで示す。
- bare-line の制御構文 (if・for・while など) は v0.8 で削除した。打つと実行前に E_UNSUPPORTED_SYNTAX で拒否し、同じ意味の S式を示す (L5)。
- doctor・init・import・trust・bug-report・explain・migrate は nshell のサブコマンドとして予約し、同名のスクリプトより優先する。同名のスクリプトは `nshell ./doctor` か `nshell -- doctor` で実行する。
- doctor の AI の点検は、プロバイダのアダプタが出す provider-check を使う (09)。
