# AI の UX ③ 承認と共有セッション

AI に任せきりにも、毎回止めるのでもなく、「危ないものだけ人が見る」を AI と人の両側で同じ形にします。

AI 側: 承認が必要と返る

```
> {"id":9,"method":"run","params":{"input":"rm -r target/"}}
< {"id":9,"result":{"ok":false,
    "error":{"code":"E_NEEDS_APPROVAL"},
    "safety":{"level":"confirm",
              "reasons":[{"rule":"classify/delete-dir",
                          "text":"deletes a directory"}]},
    "effects":[{"kind":"deletes","path":"target/",
                "size":"1.2 GB"}],
    "approval":{"id":"ap_7f3a09c4e1b2d658","expires_in_s":120}}}
… 人が承認 …
> {"id":10,"method":"run","params":{"input":"rm -r target/",
                                   "approval":"ap_7f3a09c4e1b2d658"}}
```

人の側: 同じ依頼がパネルで出る

*人の端末 (共有セッション中)*

```
~/src/nshell main ❯
╭ AI からの承認依頼 · ● confirm
│ rm -r target/
│ effects: deletes target/ (1.2 GB)
│ from: claude-code · session s_4b1
╰ Enter 承認 · Tab 説明 · Esc 拒否

ai ❯ rm -r target/                         ✓ 0.3s
```

## 共有セッション: 人と AI が同じシェルを使う

- nshell --serve --attach [PATH|ID] で、人が開いている対話セッションに AI がつながる。--mcp にも --attach を付けられる。
- ソケットは `$XDG_RUNTIME_DIR/nshell/<session>.sock`、XDG_RUNTIME_DIR がなければ `${TMPDIR:-/tmp}/nshell-$UID/` の下に置く。ディレクトリを先に 0700 で作り、ソケットは 0600。接続元の uid を確かめ、パスは macOS の sun_path の上限 (104 バイト) に収める。対話セッションの子プロセスには NSHELL_SESSION_SOCKET でソケットを知らせる。
- cwd・変数・ジョブを共有。AI のコマンドは人の端末に ai ❯ つきで流れ、人はいつでも Ctrl-C で止められる。
- 承認依頼はその端末にパネルで出る。つながっていなければ MCP の承認画面 (elicitation) を使い、どちらもなければ承認 ID を付けずに E_NEEDS_APPROVAL を返して実行しない。
- 承認を求めるのは NSHELL_AGENT=1・MCP・--serve のとき。--json の単発実行は危険度を報告するだけ (02)。
- --attach なしの --serve は AI 専用の独立したセッション。
- AI が実行したものは履歴に origin = ai で残り、人の Ctrl-R からも区別して探せる。既存の origin の proposal と agent は残し、origin:ai での検索はこの 3 つすべてに一致させる。履歴を読むときは、知らない origin のレコードも捨てずに origin を nil として読む。

## 先回りできるポリシー

- policy メソッドで規則の一覧 (名前・level・説明) を返す。AI は実行前に自分で避けられる。
- 承認 ID は `ap_` と 16 進 16 桁。1 回だけ使え、有効期限は 120 秒。セッション・入力のバイト列・cwd に結びつけるので、入力が 1 バイトでも変われば無効。期限切れのときは新しい ID つきで E_NEEDS_APPROVAL を返す。
- block は承認でも実行できない。理由と、許される代わりの書き方を fixes で返す。
- 利用者は rules.pl で confirm を足せるが、block を外すことはできない。ユーザー規則は別の rulebase で評価し、結果を confirm までに抑える (06)。
