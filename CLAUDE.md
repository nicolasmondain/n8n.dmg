# Project Rules

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short summary>
```

Types: `feat`, `fix`, `docs`, `chore`, `refactor`, `build`, `ci`, `test`, `style`, `perf`.

Scope is optional but encouraged (e.g. `docs(readme)`, `build(makefile)`, `feat(app)`).

## Code

- Shell scripts use `set -euo pipefail`
- All shared constants live in `config.sh` — scripts source it, not duplicate values
- Payload scripts (in `payload/`) run on the target machine — keep them self-contained with no build-time dependencies

## README

- Keep the README user-friendly and minimal — no CLI commands, no localhost URLs
- Technical details go in `docs/`
