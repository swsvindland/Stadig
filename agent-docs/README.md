# Agent docs

The working notes that coding agents keep while they work on Stadig. They're written for the next agent and for the owner, so they're long, dated and blunt. For how the apps work and how to build them, read [docs/](../docs/README.md) instead.

- [decisions.md](decisions.md): product calls an agent made without the owner's sign-off, the most recent near the top, each with what was decided, why, and what's still open. "You" in an entry is the owner; "mine to check" and "yours to check" say whose review it's waiting on.
- [verification.md](verification.md): what was checked by hand on a simulator or a device, and what hasn't been yet.

## Keeping them

The rules are in [CLAUDE.md](../CLAUDE.md), under "Docs to keep current". In short:

- A call the owner didn't make goes in `decisions.md` in the same change, not in a code comment or a commit message.
- Anything looked at by hand goes in `verification.md`, with the date, the branch and what wasn't run.
- An entry is a record of the day it was written. Don't rewrite old ones to match the present: add a new one.

Everything else an agent needs is beside the code: the instructions in `CLAUDE.md` (and `AGENTS.md`, which points to it), and the project's skills in `.claude/skills/` for building and testing, running an app, adding a feature, reviewing, committing and releasing.
