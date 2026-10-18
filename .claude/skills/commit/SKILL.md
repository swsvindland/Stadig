---
name: commit
description: Commit your own changes safely when other Claude Code sessions share this checkout and its git index. Use whenever committing in the main checkout of this repo, or when git status shows files you didn't change.
---

# Commit safely in a shared checkout

Several sessions often work in this checkout at once. They share one working tree and one index, so anything staged can land in whichever session commits next, and their uncommitted files aren't yours to commit. In a worktree of your own (`.claude/worktrees/<name>`), a normal `git add <your paths> && git commit` is fine; everything below is for the shared checkout.

1. **Look first.** `git status --short`. List the paths that are yours. Anything else belongs to someone else: leave it alone, don't stage, stash, reset or format it.

2. **Build the commit from a private index**, so nothing touches the shared one:

   ```sh
   export GIT_INDEX_FILE=$(mktemp -d)/index
   git read-tree HEAD
   git add -- <your paths>          # only yours
   tree=$(git write-tree)
   old=$(git rev-parse HEAD)
   new=$(git commit-tree $tree -p $old -F <message file>)
   git update-ref HEAD $new $old    # fails safely if HEAD moved; then start again from step 1
   unset GIT_INDEX_FILE
   git reset -q -- <your paths>     # so the shared index matches the new HEAD for your files
   ```

   For a shared file where someone else also has uncommitted edits (README.md, a doc), commit only your hunks: write a copy of the HEAD version with just your change applied, `git hash-object -w` it, and `git update-index --cacheinfo 100644,<hash>,<path>` in the private index instead of `git add`.

3. **Check the commit object before moving anything else**: `git show --stat HEAD`. For risky changes, build and test that exact commit in a throwaway worktree: `git worktree add --detach /tmp/check HEAD`, run the tests there, remove it.

4. **Message**: a short imperative summary of what changed for the person using the app, then a body with why and anything not verified. End with the co-author line the session's instructions give.

Never `git add -A`, `git commit -a`, `git stash` (the stash is shared too), or amend, reset or rebase another session's commit. Push only when the owner asks.
