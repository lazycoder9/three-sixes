---
name: implement
description: "Implement one GitHub issue (or a spec the user names) on the current branch, test-first, review it, and open the pull request."
disable-model-invocation: true
---

Implement the issue the user names, on the current branch. The issue is the spec.

Follow "Development process" in `DEVELOPMENT.md`: read `CONTEXT.md` and the ADRs, write the plan,
and hand each slice to a sub-agent. You orchestrate and read diffs; you do not write the code.

Use `/tdd` at the seams in the plan, each in the layer DEVELOPMENT.md "Testing" assigns (the plan
names it). Run typechecks and single test files as you go,
`MIX_TEST_PARTITION=_<branch> mix precommit` once at the end, and `/ux-check` when anything
renders. Commit.

Write the PR body with `/pr`; it is what the reviewers read. Then run `/code-review`.

Ask the user for approval, then open the pull request with `/pr`.
