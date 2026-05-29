---
description: Fixture whose allowed-tools contains a malformed token (starts with a digit) — must be rejected.
allowed-tools: Read, 123nope, Write
---

# /bad-malformed-token (fixture)

`123nope` is not tool-name-shaped (identifiers cannot start with a digit), so this
must fail validation.
