**Three Sixes** - a real-time dice-bluffing game in private Rooms, built with Phoenix + LiveView.

## Documentation Files

| File | Purpose |
|------|---------|
| `CONTEXT.md` | The domain glossary. Use its words in code, UI and docs. |
| `docs/adr/` | Decisions on record. |
| `DEVELOPMENT.md` | The development process, where tests go, and the bar for comments. |
| `docs/CODE_REVIEW.md` | **The review standard.** Every review of code in this repo runs its loop, through the `code-review` skill, inside `implement`, or with no skill at all. |
| `.claude/skills/` | The repo's own skills: `implement` (plan, delegate, test-first, review, open the PR), `code-review` (runs the standard), `pr` (the PR body in plain words, and the opening) and `retro`. |

Working material (plans, handoffs, review rounds under `notes/reviews/`) lives in `notes/`, which
is gitignored, not in `docs/`, which holds only durable, still-true documents.

## Critical

- **Model policy: every sub-agent is Opus at high effort; Fable only when the owner approves.** The main session plans, splits the work, briefs sub-agents and reviews what they return. Every spawn uses the `opus-high` agent type (`.claude/agents/opus-high.md`), which pins Opus at high effort; a bare `model: opus` runs at the session's default effort. Sub-agents do not spawn sub-agents of their own. Review round 1 also runs a second reviewer on Codex `gpt-6.1-sol`; when Codex is out of credits, Opus reviews alone.

## Workflow

- **Every branch is reviewed as a whole before its pull request opens**, by the loop in
  `docs/CODE_REVIEW.md`.
- `mix precommit` is the gate.
- The merge chain, right before merging: `git fetch origin && git rebase refs/remotes/origin/main
  && mix precommit && git push --force-with-lease`. Always spell the remote-tracking ref in full:
  a local branch named `origin/main` shadows the bare form, and the rebase silently lands on the
  wrong tip.
