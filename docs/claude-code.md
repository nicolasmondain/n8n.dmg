# Claude Code integration

Run Claude Code CLI from n8n Code nodes.

## Prerequisites

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed (`/opt/homebrew/bin/claude`)
- n8n running via the DMG installer

## 1. Authenticate Claude Code

Run the login command once on the machine:

```bash
claude login
```

This generates an OAuth token. Copy it — you will need it in the next step.

Alternatively, generate a token directly:

```bash
claude config get oauthToken
```

## 2. Store the token

Save the token in the secrets file used by the n8n launch script:

```bash
echo 'CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...' > ~/.n8n-local/secrets.env
chmod 600 ~/.n8n-local/secrets.env
```

The file must use `KEY=VALUE` format (no `export`, no quotes). One variable per line.

Restart n8n after creating or modifying the file:

```bash
n8n-dmg restart
```

## 3. Allow child_process in Code nodes

The launch script (`~/.n8n-local/bin/launch-n8n.sh`) must export:

```bash
export NODE_FUNCTION_ALLOW_BUILTIN="${NODE_FUNCTION_ALLOW_BUILTIN:-child_process,util}"
```

This is set by default in the DMG installer. It allows Code nodes to use `require('child_process')`.

## 4. Use in an n8n Code node

Create a **Code** node (JavaScript) with the following template:

```javascript
const { execFileSync } = require('child_process');

const prompt = $input.first().json.prompt ?? "Hello Claude";

// Read token from secrets file (process.env is not available in n8n task runner)
const secretLine = execFileSync('/usr/bin/grep', [
  'CLAUDE_CODE_OAUTH_TOKEN',
  '/Users/nicolas.m/.n8n-local/secrets.env'
], { encoding: 'utf-8' });
const token = secretLine.split('=').slice(1).join('=').trim();

try {
  const stdout = execFileSync('/opt/homebrew/bin/claude', [
    '-p', prompt,
    '--output-format', 'json',
    '--max-turns', '1',
    '--model', 'haiku'
  ], {
    encoding: 'utf-8',
    timeout: 30_000,
    env: {
      HOME: '/Users/nicolas.m',
      PATH: '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin',
      CLAUDE_CODE_OAUTH_TOKEN: token
    }
  });

  return [{ json: JSON.parse(stdout) }];
} catch (err) {
  return [{ json: { error: err.message, stderr: err.stderr, stdout: err.stdout }}];
}
```

### Key points

- **Full paths** are required for binaries (`/opt/homebrew/bin/claude`, `/usr/bin/grep`) because the n8n process has a minimal `PATH`.
- **`process.env` is not available** in n8n v2 Code nodes (the task runner sandbox blocks the `process` module). The token is read from the secrets file via `grep` instead.
- **`env` must be passed explicitly** to `execFileSync` — without it the child process inherits the task runner environment which lacks `HOME` and `PATH`.
- **`timeout`** prevents the workflow from hanging if Claude takes too long. Adjust as needed (default: 30 seconds).

### CLI options

| Flag | Description |
| --- | --- |
| `-p <prompt>` | Non-interactive mode with a prompt |
| `--output-format json` | Returns structured JSON output |
| `--max-turns <n>` | Limit agentic turns (1 = single response) |
| `--model <model>` | `haiku`, `sonnet`, `opus` |

## 5. Rotate the token

To rotate the token:

1. Run `claude login` again
2. Update `~/.n8n-local/secrets.env` with the new token
3. Restart n8n: `n8n-dmg restart`

No workflow changes needed — the Code node reads the file at each execution.
