---
description: Fixture with NO allowed-tools line at all — must be rejected.
---

# /bad-missing (fixture)

A command that never declares allowed-tools. Behaviour-shaping infra wants every
command explicit about its tool scope, so this must fail validation.
