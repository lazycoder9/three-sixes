# Development Guidelines

Rules and implementation patterns for Three Sixes.

## Development process

- The spec is the GitHub issue (`gh issue view N --comments`). Nothing else is.
- Before code, read `CONTEXT.md` and the ADRs in `docs/adr/`, and write
  `notes/reviews/<branch>/plan.md`: the seams to test at, the modules to call or create, the
  files expected, each product decision the issue leaves open with the option taken, and the
  neighbours of each change (docs/CODE_REVIEW.md, Spec axis), in or out and why. It is the brief
  a build agent receives.
- The main session orchestrates and reads diffs; sub-agents build each slice, on `opus-high`
  (AGENTS.md, "Model policy"). Every slice starts with a failing test at a seam from the plan,
  in the layer "Testing" below assigns.
- The PR body (the `pr` skill) carries the evidence and is what reviewers read; the review loop
  is `docs/CODE_REVIEW.md`. The PR opens only after the user approves it.

## Testing

Read this section before writing any test, and on every `/tdd` cycle: `/tdd` says how to write a
test, and this section says where the test goes.

Each test goes in the cheapest layer that can show the behaviour. The rules core is pure (ADR
0001), so most rules are pinned there, fast and without processes.

| The behaviour under test | Layer |
|---|---|
| A game rule: a Raise, a Check, a Penalty die, Knocked out, a Placement | Rules core unit test, `async: true` |
| Message order, timers, saving and restoring a Room | Room process test, with the clock passed in |
| What a person sees and can do from their seat | LiveView test (`Phoenix.LiveViewTest`), from at least two seats |
| A whole journey across browsers (create a Room, join, play a Round) | Browser test, kept to a handful |

A browser test carries a one-line reason why no lower layer can show it.

## Comments

A comment exists only when the code cannot carry the reason: a constraint from outside the code
(a browser quirk, a platform limit, a product decision with its issue number) or a why a reader
would otherwise get wrong. Everything else is the code's job: a name, a smaller function, a test.

- Say why, in one or two sentences. Numbers, sizes, file lists, "only caller", "never", "same as"
  and history ("used to", "before #12", a round id, "found by") are claims that go stale and that
  every reviewer must test; a number that matters is pinned by a test.
- A comment longer than the code under it says the code needs rewriting, not the comment.
- A change that makes a comment wrong deletes it.
- Reviews raise no finding about a comment. The comment cut at the end of the review loop
  (docs/CODE_REVIEW.md, step 4) holds every comment on the branch to this bar.
- The same bar holds for test headers. The reason on a guard's disable comment is the one comment
  a guard requires, and it is a why.
