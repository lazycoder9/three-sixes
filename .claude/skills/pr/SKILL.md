---
name: pr
description: "Write the PR body for the current branch and open the pull request. Use at the end of implement, or when the user asks for a PR."
metadata:
  credits:
    skill: pr
    author: Matt Pocock (from show-me by Dex Horthy, Humanlayer)
    url: "https://github.com/mattpocock/skills/blob/main/skills/in-progress/pr/SKILL.md"
---

Write the PR body with this template, then open the PR (see "Opening").

```markdown
## Summary

<two or three plain sentences: what a user will notice, and why it changed>
<a diagram, diff-sketch or tree, only when it says it faster than words>

Closes #N

## Evidence

- **Before:** <the failing test run, or a screenshot>
  **After:** <the passing run, or a screenshot>

## Review

<the table from notes/reviews/<branch>/disposition.md, or "not reviewed yet">

## Merge danger

**Door:** one-way or two-way
**Blast radius:** <what else this can break>
```

## Words

The reader has no context and no technical training. Write so a child could follow:

- Short sentences. One idea each. Common words.
- No jargon, no acronyms, no internal names. Say "the game table", not "RoomServer".
- No file paths in prose. A file name goes in a code span only when the reader must open it.
- Say what changed for a person using the product before you say how.
- The Summary fits on a phone screen. If a sentence needs a second reading, rewrite it.

## Sections

**Summary.** Pick the smallest view that makes the point: pseudocode for logic, a call tree for
control flow, a component or file tree for structure, a `diff` sketch when the shape already
exists and only the change matters, Mermaid for data flow. One visual at most, usually none.

**Defaults.** Each product choice the issue left open, and this PR made without the owner's word,
is a line in the Summary marked "default, not confirmed by owner". Later audits read these lines to
tell an agent's default from an owner's call.

**Evidence.** Screenshots when the change is visual. Otherwise the exact test that failed before
and passes now, pasted. A promise is not evidence.

**Review.** The disposition table from `docs/CODE_REVIEW.md`, one row per finding. A branch with
no disposition has not been reviewed; say so in this section instead of leaving it out.

**Merge danger.** A two-way door can be rolled back cheaply; a one-way door cannot (a migration,
a deleted column, a changed public shape). The blast radius names what else can break: other
pages, mobile, consumers of a changed shape.

## Commits

A subject under 60 characters, then two to four plain bullets, each one visible effect. No
history, no file paths, no essays. Review-round commits are `Review round N: <x> fixed, <y>
declined` with the same bullets. Trailer: `Co-Authored-By: Claude <noreply@anthropic.com>`.

## Opening

1. The title reads like the commit subject and describes only this diff.
2. Ask the user for approval. Do not open a PR without it.
3. Merge chain from `AGENTS.md` first (fetch, rebase onto `refs/remotes/origin/main`, precommit,
   push with lease), then `gh pr create --title "<title>" --body-file <file>`.
4. Register the PR with `link_pull_request` when that tool exists.
