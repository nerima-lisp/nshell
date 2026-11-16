# cl-prolog-kit をもっと活かす

## いまの使い方

補完の知識ベースだけで使っており、規則は 3 本 (登録コマンド・サブコマンド・フラグから completes を導く)。実質は表引きです。一方 cl-prolog-kit 自体は、cut・否定・findall / setof・assert・tabling・CLP(FD)・DCG・foreign predicate・.pl ファイルの読み込みまで備えています。

表引きだけなら Prolog は要りません。使い方を変えれば、nshell の中核になれます。

## 考え方: 1 つの「シェル知識ベース」を全機能で共有する

シェルが知っている事実をすべて 1 つの rulebase に集め、補完・危険度判定・エラー診断・型検査が同じ規則に問い合わせます。規則はデータなので、人も AI も読めて、書き足せて、テストできます。

事実の供給元

- builtin の spec
- コマンドカタログと --help の解析結果
- 履歴 (cwd・status・所要時間)
- ジョブ・環境変数・abbr
- git の状態 (必要なときだけ)
- ファイルの種類・場所 (必要なときだけ)

›

シェル知識ベース

- 事実: command / flag / effect / produces …
- 規則: classify / diagnose / next_stage …
- ユーザー規則: ~/.config/nshell/rules.pl
- 外部状態は foreign predicate で遅延取得

›

問い合わせる側

- 補完とハイライト
- explain と危険度 (safe / confirm / block)
- ai why の一次診断
- 値パイプラインの型検査
- S式の (?- …) と MCP の query
- nshell doctor

### A. 安全ポリシーを規則で書く

追加

いまの静的解析 (safety.lisp 約500行) を規則に置き換える。証明に使った規則がそのまま「理由」になり、explain・--json・MCP の承認画面に出せる。利用者は rules.pl で自分の規則を足せる。

以下は規則の概略。safe 用の許可仕様は `packages/feature/kb/src/domain/classify-rules.lisp` の `+safe-command-specs+` に置く。照合は `packages/feature/kb/src/domain/predicates.lisp` で行い、結果を `spec_match` の事実として規則に渡す。

```
classify(C, block, 'ルートの再帰削除') :-
    command(C, rm), flag(C, recursive),
    operand(C, P), root_path(P).
classify(C, confirm, 'ディレクトリの再帰削除') :-
    command(C, rm), flag(C, recursive),
    operand(C, P), \+ root_path(P).
classify(C, confirm, '強制 push') :-
    command(C, git), subcommand(C, push), flag(C, force).
classify(C, confirm, 'プロジェクト外への書き込み') :-
    effect(C, writes(P)), \+ inside_project(P).
classify(C, confirm, '未知のコマンド') :-
    \+ known_command(C).
classify(C, confirm, '許可仕様に合わない引数') :-
    known_command(C), \+ spec_match(C).
classify(C, safe, '許可仕様に一致するコマンド') :-
    spec_match(C).
```

- 規則は findall ですべて評価し、最も高いレベルを採る。同じレベルの規則は、すべて reasons[] に入れる。
- safe にするのは、コマンド名・すべての引数・リダイレクト・代入の前置きが許可仕様 (spec) に一致するものだけ。未知のコマンドや spec に一致しないものは confirm、ルート以外への rm -r は confirm、ルートの再帰削除は block。
- S式では、コマンドを `^` で明示しない形とリダイレクトに confirm の規則を適用する。
- 変わる既存の期待値は、理由ごとに移行テストの表へ書く。
- 規則名は classify/<kebab> (classify/delete-dir など) とし、組み込みの規則は 1 つのデータファイルにまとめる。
- 安全判定の効力を持つのは、Enter のときの判定と、実行のゲートの判定。AI の提案を受け取ったときと explain のときにも判定するが、これは表示 (`[safe]` などの印) と、block の提案を入力欄に入れないことにだけ使う。入力中の表示は P3-7 で行う。

使うエンジン機能: findall・否定・foreign predicate

### B. コマンドの効果モデル

追加

各コマンドが「読む・書く・消す・ネットワーク・権限昇格」のどれをするかを事実で持ち、パイプラインやリダイレクトを通して合成する。A の判定と、実行前の要約 (src/ を削除・ネットワーク接続あり) に使う。

```
effect(C, deletes(P)) :- command(C, rm), operand(C, P).
effect(C, writes(P))  :- redirect(C, '>', P).
effect(C, network)    :- command(C, N), network_command(N).
network_command(curl).  network_command(ssh).

pipeline_effects(Pl, Es) :-
    setof(E, S^(stage(Pl, S), effect(S, E)), Es).
```

読む効果 (reads) は、どのコマンドがどの引数を読むかを事実に書いたものにだけ付ける。事実は `packages/feature/kb/src/domain/classify-rules.lisp` の `path-operand-reader` などに置く。

- cat・ls・wc・stat・file・head・tail のオペランドは、すべて読むパスとして扱う。オペランドは、そのコマンドの許可仕様 (spec) の行がオペランドとして読む語だけで、オプションの値は含まない。spec の行に書いていないオプションが引数にあるときは、どの語がその値かを決められないので、読む効果を付けない。
- オペランドのない ls と git status は、作業ディレクトリ `.` を読む。
- 標準入力だけを読むもの (オペランドのない cat や wc、パイプラインの `wc -l`) には、読む効果を付けない。置換を含むオペランドも、読むパスが入力に書かれていないので、読む効果を付けない。
- オペランドの `-` を標準入力として読むかはコマンドによるので、spec の行に書く。`-` を標準入力とみなすのは、どの環境でも標準入力として読むコマンド (cat と file) だけで、`--` のあとでも同じにする。ほかのコマンドでは、`-` を読む効果を付ける。ls はどの環境でもファイル `-` を読み、wc・head・tail・stat は macOS ではファイル `-` を、GNU では標準入力を読む。

効果は、A の安全判定が判定するコマンドごとに集める。置換の中のコマンド、ラッパーや sh -c・eval が実行するコマンド、エイリアスを展開したあとのコマンドもここに入る。判定はするが実行しないコマンド (不明なコマンドのオペランドに書かれたコマンドや、引用符で囲んだヒアドキュメントの本文にある置換など) には、効果を付けない。

使うエンジン機能: setof・事実の合成

### C. ai why の一次診断をオフラインで

追加

失敗したコマンドの status・stderr・文脈から、規則で原因と修正案を出す。決定的で速く、理由も示せる。規則に当たらないときだけ LLM に渡す。AI に規則とテストを書かせやすい。diagnose/typo の 1 本だけは、02 の例 (E_COMMAND_NOT_FOUND の fixes) を golden test として通すため、P1 で先に入れる。

```
diagnose(R, fix(New), 'コマンド名の打ち間違い') :-
    status(R, 127), command_name(R, Bad),
    known_command(Good), edit_distance(Bad, Good, D),
    D =< 2, retype(R, Good, New).
diagnose(R, fix('git pull --rebase'), 'リモートが先行') :-
    command(R, git), subcommand(R, push),
    stderr_has(R, 'non-fast-forward').
```

使うエンジン機能: foreign predicate (編集距離・stderr 検索)

### D. 値パイプラインの型検査

追加

ビルトインが返すレコードの型と、変換が受け取る型を事実で持つ。-> の連鎖を実行前に検査し、型に合う次の段だけを補完する。to-json の差し込みなど修正案も出せる。

```
produces(jobs,    list(record(job))).
produces(history, list(record(history))).
transforms(where,   list(T), list(T)).
transforms(select,  list(record(_)), list(record(partial))).
transforms(to_json, _, text).

next_stage(In, F) :- transforms(F, In, _).
```

使うエンジン機能: 単一化による型の照合

### E. 文法としての補完 (DCG)

簡素化

コマンドの引数の並びを DCG で書く。入力途中の行を解析すれば「次に来られるもの」が分かり、補完・誤ったフラグのハイライト・排他オプションの検査が 1 つの定義から出る。--help の解析結果もこの形に変換する。補完の rulebase は A・B (P1) のものを共用する。--help を実行するコマンドは、今の許可リストとキャッシュのまま変えない。

```
git     --> [git], git_sub.
git_sub --> [checkout], branch.
git_sub --> [commit], commit_opts.
commit_opts --> [].
commit_opts --> ['-m'], message, commit_opts.
commit_opts --> ['--amend'], commit_opts.
branch  --> [B], { git_branch(B) }.
```

使うエンジン機能: DCG・foreign predicate (git ブランチ)

### F. 論理クエリをシェル言語に入れる

追加

S式に (?- …) を足し、履歴・ジョブ・ファイルなどの事実へ問い合わせて結果をレコードで返す。-> にそのまま流せる。--serve と MCP にも query として出し、AI が推測せずに事実を引けるようにする。

```
(?- (history ?cmd :cwd ?dir :status ?s)
    (/= ?s 0)
    (prefix ?cmd "make"))

(-> (?- (has-flag tar ?f) (describes tar ?f ?d))
    (select :f :d)
    (to-json))
```

使うエンジン機能: findall・tabling (再帰的な問い合わせ)

### G. nshell doctor と次のコマンドの提案

追加

設定の矛盾 (コマンドを隠す abbr、キー割り当ての衝突、ループする alias) を規則で検出する。直前の結果と状態から次の一手を提案する (commit 後で先行していれば push)。

```
problem(abbr_shadows(A)) :-
    abbr(A, _), command_on_path(A).
problem(key_conflict(K)) :-
    binding(K, A1), binding(K, A2), A1 \== A2.

suggest('git push') :-
    last(C, 0), command(C, git), subcommand(C, commit),
    branch_ahead.
```

使うエンジン機能: 否定・findall

## AI フレンドリーになる理由

- 判定の理由が証明として残るので、--json と MCP に「なぜ confirm なのか」を構造化して返せる。
- 規則は小さく独立しているので、AI に「この失敗の診断規則を書いて、テストも足して」と頼みやすい。
- AI はコマンドの使い方を推測せず、query で知識ベースに聞ける。
- ポリシーを MCP のリソースとして公開すれば、エージェントが実行前に自分で検査できる。

## 性能と安全の注意

- 文法と組み込みの規則はビルド時にコンパイルする。キー入力の経路ではファイル I/O とプロセス起動をしない。
- 知識ベースへの問い合わせは入力の区間をキーにしてキャッシュし、推論数と時間の上限を付ける。
- git やファイルなど外部の状態は foreign predicate で必要なときだけ取り、タイムアウトをかける。
- call_with_depth_limit と既存の資源上限で暴走を止める。
- プレビューとあいまい検索は非同期で動かし、取り消せるようにする。
- ユーザー規則は組み込み規則と別の rulebase で評価し、結果を confirm までに抑える。安全判定は緩められず、block は組み込み規則だけが出せる。rules.pl を読むのは P5 (ユーザー規則の制限と同時) で、P1 では仕組みとテスト用の注入だけを作る。

## 導入順

- 1. A と B (P1 の explain と同時に): 危険度判定を規則に移す。効果が最も大きい。C の diagnose/typo もここで入れる。
- 2. C の残り (P4 の ai why と同時に)。
- 3. D と E (P3 の補完の作り直しで)。
- 4. F と G: 言語と MCP への公開、doctor。

cl-prolog-kit は残す依存として扱い、補完の Prolog 部分は「作り直し」と判定しています (01・I6)。
