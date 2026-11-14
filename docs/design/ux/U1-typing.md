# 人間の UX ① 入力しているとき

打っている間に「何が起きるか」が分かり、確定した行は静かに畳まれる。目標は fish の気持ちよさに、S式と安全判定の情報を足すことです。

*入力中 (上) と、確定済みの行 (下: transient prompt)*

```
~/src/nshell  main ↑1 ●                       2.3s · 14:32
❯ git commit -m "tidy reader" --amend

❯ make test                                         ✓ 0.8s
❯ ls src                                                 ✓
```

*補完メニュー: 種類と説明をそろえて表示*

```
~/src/nshell main ❯ git checkout re
 ▸  release/0.8    branch · 2 日前
    refactor/kb    branch · 5 日前
    README.md      file · 変更あり
    --recurse-submodules  submodule も更新
  4 件 · Tab 次へ · Shift-Tab 前へ · Enter 決定
```

*値パイプライン: 型に合う次の段だけ (06-D)*

```
~/src/nshell main ❯ (-> (jobs) █
   records(job) に続けられる変換
 ▸  where     条件で絞る
    select    列を選ぶ
    sort-by   並べ替え
    to-json   JSON テキストにする
```

*実行前の危険度: 人が打ったものは止めずに知らせる*

```
~/src/nshell main ❯ rm -rf /
  ● block  ルートの再帰削除 · もう一度 Enter で実行

~/src/nshell main ❯ rm -r build
  ● confirm  build/ を削除 (214 ファイル)
```

## 見た目の方針

背景

#1E1F29

文字

#F8F8F2

コマンド

#8BE9FD

パス

#BD93F9

git

#FF79C6

成功・safe

#50FA7B

注意・confirm

#FFB86C

エラー・block

#FF5555

文字列

#F1FA8C

- 既定テーマを Dracula (既存のプリセット) にする。16 / 256 色へは自動で落とし、明るい背景では solarized-light を勧める。
- 記号は標準 Unicode だけ (❯ › ▸ ● ✓ ✗ ↑ ↓ と罫線 ╭)。Nerd Font は任意で、なくても崩れない。
- ui :classic では、確定した行を ❯ と結果 (✓ / ✗・所要時間) だけに畳む transient prompt。既定の ui :rich では U9 のブロック表示がこの役を担う。
- 右プロンプトは意味があるときだけ出す: 失敗の status、2 秒以上の所要時間、ジョブ数。ステータスライン (U9) を出しているときは右プロンプトを出さない。
- パネル類 (補完・提案・ヘルプ) は同じ罫線・余白・見出しの形にそろえる。
