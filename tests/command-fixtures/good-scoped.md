---
description: Well-formed fixture using the broader allowed-tools grammar — scoped Bash and an MCP tool name. Proves the shape check is permissive, not registry-bound.
allowed-tools: Read, Bash(git diff:*), mcp__server__tool
---

# /good-scoped (fixture)

Not a real command. Documents that `Tool(scope)` and `mcp__server__tool` tokens are
intentionally accepted by `scripts/check-allowed-tools.sh` (shape, not membership).
