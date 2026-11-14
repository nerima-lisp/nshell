# 体験をさらに上げる — 待たせず、使い回せて、迷わない

ここまでの設計 (U1〜U4) の上に足すアイデアです。どれも、既にある履歴の記録 (cwd・status・所要時間)、値パイプライン、知識ベース (06) を土台にしているので、新しい仕組みを増やさずに済みます。

*出力ストア: 直前の出力を値として使う*

```
~/src/nshell main ❯ cargo test
test result: FAILED. 41 passed; 3 failed
✗ 101  · 出力は (out) に保存
❯ (-> (out) (where (match :text "FAILED")))
 line  text
 212   parser::tests::here_doc FAILED
 388   lexer::tests::unicode  FAILED
 401   lexer::tests::emoji    FAILED
```

*レコードは自動で表に。(view) で対話的に*

```
❯ (-> (jobs) (select :id :state :command))
 id  state     command
 1   running   npm run dev
 2   stopped   vim README.md
 3   done      cargo build --release
 3 rows · (view) で絞り込み・並べ替え
```

*Ctrl-R: あいまい検索と、場所・結果での絞り込み*

```
history › mk tst     [この dir] [失敗] [ai]
 ▸  make test             ✓ 0.8s · 2 分前
    make test-fast        ✓ 0.3s · 昨日
    make -C t smoke       ✗ 2   · 3 日前
  cwd ~/src/nshell · Tab で絞り込みを切り替え
```

*cd: よく行く場所へ数文字で*

```
~/src/nshell main ❯ cd nshell
 ▸  ~/src/nshell          312 回 · 今日
    ~/src/nshell/docs     41 回 · 先週
    ~/work/nshell-bench   3 回 · 先月
  履歴の cwd から頻度と新しさで順位づけ
```

## どこから手をつけるか

すぐ効く

効果 大 · 手間 小

- 非同期プロンプト
- あいまい履歴検索と絞り込み
- 頻度順の cd
- 括弧の自動ペアと色分け
- 長いコマンドの通知

大きな賭け

効果 大 · 手間 大

- 出力ストア
- 表の自動表示と (view)
- プロジェクト設定と Nix 統合
- bash からの書き換え

ついでに

効果 中 · 手間 小

- clip
- Alt-T のファイル挿入
- 改行時の自動インデント
- 色覚に配慮したテーマ
- スクリーンリーダー向け (ui :plain)

あとで

効果 中 · 手間 大

- 状況に応じたセグメント
- 履歴の共有
- nshell profile

### 待たせない

非同期プロンプト

追加

プロンプトはすぐ出し、git の状態などは取れたら差し替える。キー入力を外部コマンドで止めない。

長いコマンドの通知

追加

10 秒以上かかって端末が裏にあるとき、終わったらデスクトップ通知 (OSC 9 / 777)。タイトルにも進行を出す。

nshell profile

追加

起動・プロンプト・補完のどこが遅いかを表示。性能の予算そのものは 08 で CI に入れる。

### 出力を使い回す

出力ストア

追加

各コマンドの出力を上限つきで保持し、(out) や (out -2) で (:line :text) のレコードとして取り出す。--private では保存しない。ai why もここを読む。

表の自動表示と (view)

追加

値位置のレコードは揃えた表で出す。(view) で絞り込み・並べ替え・列の選択を対話的に。

clip

追加

値や出力をクリップボードへ (OSC 52、macOS は pbcopy)。マウスを外しても困らない。

### 探す・移動する

あいまい履歴検索

残す

Ctrl-R をあいまい一致にし、この dir・失敗・AI 実行で絞り込む。履歴が既に cwd と status を持っているので追加の記録は不要。

頻度順の cd

追加

履歴の cwd から「よく行く・最近行った」場所を順位づけ。cd の補完と cd 数文字 で移動。

ファイルのあいまい挿入

追加

Alt-T でファイル名をあいまいに探して入力欄に入れる (Ctrl-T は文字の入れ替えのまま)。

### 場所に合わせる

プロジェクト設定

追加

.nshell.lisp でそのリポジトリ用の abbr・関数・rules.pl を読む。初回は nshell trust で許可したものだけ (direnv と同じ考え方)。

Nix との統合

追加

flake.nix のあるディレクトリでは nix develop の環境を取り込むか 1 行で提案。プロンプトに Nix 環境の印。

状況に応じたセグメント

追加

kubectl や aws を打っているときだけ context をプロンプトに出す。規則で書く (06)。

### S式を書きやすく

括弧の自動ペアと色分け

追加

( で ) を補い、入れ子の深さで括弧の色を変える。対応括弧のハイライトと合わせて。

改行時の自動インデント

追加

開いた括弧の中で Enter したら続きの行を揃える。複数行の S式が読みやすくなる。

bash からの書き換え

追加

bash の for や if を貼ると、同じ意味の S式を提案 (規則で変換、無理なら AI)。移行の壁を下げる。

### 誰でも使える

スクリーンリーダー向けモード

追加

再描画の小技を使わず、変化を素直な行として出す。U9 の ui :plain で実現する。

色覚に配慮したテーマ

追加

safe / confirm / block を色だけでなく記号と明度で区別 (● ▲ ■)。高コントラスト版も。

履歴の共有

追加

複数の端末で履歴をプロンプトごとに同期。各セッション内の順序は保つ。
