---
name: review-change
description: Review a diff in this repo for bugs, leaks, concurrency and performance problems, missing tests and docs before it's committed or merged. Use before committing a feature or fix, when asked to review a branch or PR, or after another session's work lands.
---

# Review a change

Read the whole diff (`git diff`, or `git diff main...<branch>`), then the code around each hunk. Check, in order:

## Correctness
- Does it do what the design doc and `docs/<app>.md` say? Edge cases: empty history, first day, a week boundary, DST, a different locale or unit system, an iPad width, large text.
- Data from users, files, the store, Health or the network: no force unwraps, `try!`, unchecked indexing, or division by a count that can be zero.
- Stored or shared payloads: schema version bumped and an old-shape decoding test when the shape changed. Deletes are tombstones, not hard deletes, where sync is involved.

## Lifetimes and leaks
- Observers, timers, `Task`s that loop or await streams, delegates, Combine sinks: captured `[weak self]`, stored, cancelled or removed. A `Task` started in a view belongs in `.task`.
- Caches with a bound. No growing arrays on long-lived objects.

## Concurrency
- Heavy work off the main actor (catalog search, analysis, decoding, Vision, image work); UI state set on the main actor.
- `@unchecked Sendable`, `nonisolated(unsafe)`, locks: justified in a comment and actually safe. Continuations resumed exactly once.

## Performance
- Nothing expensive in `body` or in computed properties a view reads repeatedly. Formatters and regexes created once.
- No O(n²) over histories that grow every day.

## Tests and tooling
- New logic has package tests, and what a changed flow decides is tested below the UI. Tests are deterministic.
- `Scripts/build.sh lint` clean; zero warnings; project files only changed through the generator.

## Docs
- `docs/<app>.md`, `docs/decisions.md` (calls made without sign-off), `docs/verification.md` (what was checked by hand) updated where they should be.

Report findings most severe first, each with file:line, what goes wrong and the fix. Don't pad with style nits the formatter would settle.
