# U01: Read shell state over MCP

## Procedure

1. Set `XDG_STATE_HOME` to a temporary directory and export it so both processes inherit the same value. Start nshell interactively with that environment, run `echo U01_MCP_STATE_OK`, wait for the next prompt, and exit.
2. Start `nshell --mcp` as a separate stdio process with the same `XDG_STATE_HOME` value. Send these newline-delimited JSON-RPC messages:

   ```json
   {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"scenario","version":"1"}}}
   {"jsonrpc":"2.0","method":"notifications/initialized"}
   {"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
   {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_sessions","arguments":{}}}
   ```

3. Record the transcript session ID returned by `list_sessions`. Replace `<SESSION_ID>` below with that value and send the request:

   ```json
   {"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"read_state","arguments":{"session_id":"<SESSION_ID>","tail_lines":50}}}
   ```

4. Inspect the returned snapshot and transcript content, then terminate the MCP process by closing stdin.

## Pass condition

The server advertises `list_sessions` and `read_state`. `list_sessions` reports the transcript session and snapshot availability. `read_state` returns the snapshot and a transcript tail containing `U01_MCP_STATE_OK`. All files remain under the temporary state directory.
