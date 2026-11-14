# AI プロバイダ — Claude Code / Codex / Ollama

AI 支援の接続先を 3 つから選べるようにします。既定は Claude Code。どれを選んでも、提案の形・安全判定・承認の流れ・キー操作は同じです。

*切り替えと確認*

```
~/src/nshell main ❯ ai status
  provider  claude-code  (既定)
  送信先    Anthropic (Claude Code のログイン)
  model     CLI の既定
  確認      ✓ ツールなし · MCP なし · 構造化出力

~/src/nshell main ❯ ai set provider ollama
  ● ollama · localhost:11434 · データは外に出ません
  model を選んでください: ai set model qwen3
```

## 共通の約束 (どのプロバイダでも同じ)

- AI は提案を返すだけ。実行するのは nshell で、必ず人の Enter と危険度判定 (06-A) を通る。
- 送る文脈は同じ redaction を通した同じ内容 (直前コマンド・status・cwd・git・出力末尾・環境変数名)。
- 受け取る形は 1 つの JSON Schema (command・説明・前提)。合わなければ 1 回だけ再要求し、だめなら失敗として表示。
- ? ・ Ctrl-] ・ ai why ・ ai explain ・ agent はすべてのプロバイダで使える。
- --private のときは transcript を残さない (codex は --ephemeral)。

## 3 つのプロバイダの違い

|   | claude-code (既定) | codex | ollama |
|---|---|---|---|
| 起動 | claude CLI をストリーミング JSON で | codex exec --json --ephemeral。空の一時ディレクトリを cwd にし、MCP は設定で無効にする | HTTP: localhost:11434/api/chat (cl-ollama-kit v3、cl-http-kit 経由) |
| 提案の受け取り | 構造化出力 (StructuredOutput のみ許可) | --output-schema で JSON Schema を指定 | format に JSON Schema を指定 |
| ツールを使わせない | ツール一覧が空・MCP なしをマニフェストで起動時に確認 (既存) | --sandbox read-only。起動引数を確かめる。item の種類が agent_message か reasoning 以外 (command_execution・file_change・mcp_tool_call・collab_tool_call・web_search・todo_list) ならその回を打ち切る。turn.failed と error は失敗として扱う | tools を付けずに要求し、tool_calls を含む応答は拒否する。起動時に /api/version と /api/tags を確かめる |
| 認証 | Claude Code のログイン | codex のログインか API キー | 不要 (ローカル) |
| データの送信先 | Anthropic | OpenAI | 自分のマシン (OLLAMA_HOST を変えればその先) |
| model の指定 | ai set model (なければ CLI の既定) | ai set model (-m に渡す) | ai set model は必須 |
| オフライン | × | × | ○ |

## 選び方

```
ai set provider claude-code    ; 既定
ai set provider codex
ai set provider ollama
ai set model qwen3

;; init.lisp
(ai-provider :ollama :model "qwen3"
             :host "http://localhost:11434")

;; 環境変数
NSHELL_AI_PROVIDER=codex
NSHELL_AI_MODEL=gpt-5.5
```

- 既定は claude-code。NSHELL_AI_COMMAND は「同じプロトコルの別実行ファイル」として残し、上級者向けに。
- effort など各プロバイダ固有の設定は、対応するものがあれば変換し、なければ無視したことを ai status に出す。

## 安全と分かりやすさ

- 使えないときに別のプロバイダへ勝手に切り替えない。送信先が変わるため。代わりに理由と直し方を出す。
- プロバイダを切り替えたとき、そのセッションで初めて使うときに、送信先を 1 行で表示。
- プロンプトの {ai} は名前の頭文字で表示 (cc / cx / ol)。
- nshell doctor が 3 つすべてを点検: 実行ファイル・ログイン・ollama の model 一覧と接続。点検には P4 のアダプタが出す provider-check を使う。
- codex がサンドボックス内でコマンドを実行しようとしたら、その回は打ち切り、提案として扱わない。
- codex では、打ち切る前にファイルを読まれる余地が残る。このリスクは ai set provider codex で切り替えたときと docs に表示する。
