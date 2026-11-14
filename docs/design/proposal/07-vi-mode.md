# vi モード — fish_vi_key_bindings と同等に

vi モードは残し、fish の vi キー操作と同じ体験にします。fish のソース (fish_vi_key_bindings.fish と共有キー定義) と nshell の実装を 1 キーずつ突き合わせた結果です。

あり

18

変更

5

追加

26

*モード表示とカーソル形状*

```
[N] ~/src/nshell  main
❯ (echo ,(+ 2 3))
  di( → (echo ,())     %  → 対応する ) へ

[R] ~/src/nshell  main
❯ git checkout main
  R: 上書き入力 · カーソルは下線
```

## 同等であることの確かめ方

- fish の挙動を「キー列 → 入力欄とカーソルの結果」の表として書き出し、そのまま reducer の単体テストにする。input-state は純粋な値なので端末なしで回る。
- fish のバージョンを固定して差分を確認 (今回の調査は 2026-11-11 の fish main の fish_vi_key_bindings.fish)。
- 日本語などの全角文字・結合文字の上での移動と削除もテストに含める (既存の grapheme 処理を流用)。
- 既存の vi テスト (約 660 行) は残し、上の表に統合する。

### モードと切り替え

|   |   |   |
|---|---|---|
| normal (default) / insert / visual | [あり] | 3 モードと d・c の operator 待ち |
| replace (R) | [追加] | 上書き入力。Backspace で戻る |
| replace_one (r) | [あり] | 1 文字置き換え |
| 初期モード | [追加] | fish と同じく insert で開始。init.lisp で default / visual も選べる |
| Esc | [あり] | normal へ移り 1 文字左へ、補完メニューも閉じる |
| Ctrl-C (normal) | [変更] | 入力は消える。fish と同じく、そのあと insert へ戻す |
| set -o vi / NSHELL_VI_MODE | [あり] | 切り替え手段は維持 |

### 移動

|   |   |   |
|---|---|---|
| h l w b e 0 ^ $ gg G | [あり] |  |
| f F t T ; , | [あり] |  |
| 数値の前置 (3w など) | [あり] |  |
| W B E ge gE | [追加] | 空白区切りの bigword と、後ろ向きの語末 |
| % | [追加] | 対応する括弧へ。S式でいちばん使う |
| _ g^ g$ | [追加] | 行頭・行末の別名 |
| k / j | [変更] | いまは単純な履歴の前後。fish と同じく入力中の文字列での前方一致検索に |
| [ / ] | [追加] | カーソル位置のトークンで履歴を検索 |

### 編集

|   |   |   |
|---|---|---|
| x D C s d{動き} c{動き} y{動き} dd cc yy | [あり] |  |
| p P u Ctrl-R (redo) | [あり] |  |
| X S Y | [追加] | 前の文字を削除・行を置き換え・行をヤンク |
| o O | [追加] | 下・上に行を開いて insert |
| J | [追加] | 次の行と連結 |
| ~ g~{動き} gu gU | [追加] | 大文字小文字の切り替え |
| Ctrl-A / Ctrl-X | [追加] | カーソル下の数値を増減 |
| # | [追加] | 行全体をコメント化して履歴に残す。bare-line は #、S式の行は ; を付ける。もう一度で外れる |
| gp | [追加] | ヤンクの巡回 (yank-pop) |
| d; d, | [追加] | 直前の f / t の範囲を削除 |

### テキストオブジェクト

|   |   |   |
|---|---|---|
| iw aw i" a" i' a' i( a( i[ a[ i{ a{ | [あり] |  |
| iW aW | [追加] | bigword |
| ib ab | [追加] | カーソルを囲む最も内側の括弧 (種類を問わない) |
| i{文字} a{文字} | [追加] | 任意の文字の対で囲まれた範囲 (fish の d,i / d,a) |

### visual

|   |   |   |
|---|---|---|
| v o d x c s y i a | [あり] |  |
| ~ gu gU | [追加] | 選択範囲の大文字小文字 |
| X I # | [追加] | 行削除・行頭から insert・コメント化 |

### クリップボード

|   |   |   |
|---|---|---|
| "*y "+y "*p "+p "*yy | [追加] | システムのクリップボード (OSC 52 / pbcopy / wl-copy)。U8 の clip と共通 |

### insert モードで共有するキー

|   |   |   |
|---|---|---|
| Tab Shift-Tab → Ctrl-F (候補受け入れ) | [あり] |  |
| Ctrl-N | [追加] | 候補の受け入れ (fish の vi insert と同じ) |
| Ctrl-Y Alt-Y Ctrl-U Ctrl-K Ctrl-W Ctrl-L Ctrl-D | [あり] |  |
| Alt-. Alt-S Alt-E Ctrl-R | [あり] |  |
| F1 / Alt-H Alt-# | [追加] | コマンドの説明 (U4)・コメント化 |
| Space ; \| & > で abbr 展開 | [あり] |  |

### 表示と設定

|   |   |   |
|---|---|---|
| カーソル形状 | [変更] | normal = ブロック、insert = バー はあり。replace = 下線を追加 |
| モード表示 | [追加] | プロンプトに {vi-mode} セグメント ([N] [I] [V] [R])。fish_mode_prompt 相当 |
| モード別の bind | [追加] | bind -M insert KEY ACTION のようにモードを指定 |
| hybrid | [追加] | 全モードで emacs 系のキーも使える設定 (fish_hybrid_key_bindings 相当) |
| Esc の待ち時間 | [追加] | Alt キーと区別する待ち時間を ms で設定 (fish_escape_delay_ms 相当) |

### fish に合わせる細部

|   |   |   |
|---|---|---|
| 単語の区切り | [変更] | fish と同じく _ を区切りとして扱う (w は foo_bar の _ で止まる) |
| cw | [変更] | fish と同じく dw のあと insert (次の単語の先頭まで消す)。vim の cw は ce |
| normal での行末 | [あり] | カーソルは最後の文字の上まで (inclusive) |

### nshell 独自で残すもの

|   |   |   |
|---|---|---|
| . | [あり] | 直前の変更の繰り返し (fish の既定にはない) |
| Ctrl-] / ? | [あり] | AI への問い合わせは vi の各モードからも同じキーで (U3) |
