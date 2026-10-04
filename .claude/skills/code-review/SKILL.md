---
name: code-review
description: "Review this branch against main by the loop in docs/CODE_REVIEW.md. Use when the user asks for a review, or when implement reaches its review step."
---

Run the loop in `docs/CODE_REVIEW.md` on the current branch. That document is the standard: the
axes, the finding format, the outcome lines and the stop rule live there and nowhere else. This
skill is the procedure that runs it. Read the standard once, in full, before step 0.

You are the orchestrator. Reviewers and fix agents run as sub-agents through the Agent tool with
`subagent_type: opus-high`, one job per agent, and never spawn agents of their own. Round 1 adds a second
reviewer on Codex (`codex exec`, step 1). Everything they write goes to files;
you read files, not transcripts.

## Inputs

- `BRANCH`: `git rev-parse --abbrev-ref HEAD`. `REVIEW_DIR`: `notes/reviews/$BRANCH/` (`mkdir -p`).
- The spec: the issue number from the branch name, the commit messages (`#123`, `Closes #45`), or
  the argument the user passed; `gh issue view N --comments`. With no spec, say so and run the
  Spec axis against the PR body alone.
- The PR body drafted by the `pr` skill (its Evidence section: red and green runs, shots and their
  readings), when this runs inside `implement`.

## Steps

0. **Base and journey** (standard, step 0). On rebase conflicts, one Opus agent resolves and
   stages, then you read every conflicted hunk before `git rebase --continue`. The gate runs on a partition:
   `MIX_TEST_PARTITION=_review_$$ mix precommit`. Then write `REVIEW_DIR/base.md` with one line
   each: the rebased head; the `refs/remotes/origin/main` sha; the diff command
   `git diff refs/remotes/origin/main...HEAD` (always the full ref: a local branch named
   `origin/main` shadows the bare form and the diff then hides commits already on main);
   the commit list; the blast radius, which is `git grep -ln <name>` for every exported symbol,
   constant, column, translation key or config key the diff adds or changes, with the files listed
   under each name.

   Journey: walk the journey the spec changes in the real app yourself (the `run` skill), starting
   from a fresh Room, with a second Player in another browser when the journey has more than one
   seat, and including a reload mid-Game when the journey has one. Append each shot to `REVIEW_DIR/evidence.md` with a
   one-line reading of what it shows against the spec. Done when the gate is green, `base.md`
   exists, and `evidence.md` holds the journey or the one line saying no user journey passes
   through the branch.

1. **Review round 1** (standard, step 1). Two reviewers on the same prompt, each holding all four
   axes: one Opus sub-agent and one Codex `gpt-6.1-sol` run at high effort, at every branch size.
   The scripts live in `.claude/skills/code-review/scripts/`.
   - **Inputs.** `REVIEW_DIR` holds `base.md`, `evidence.md` and `issue.md`: the issue text, plus
     the parent spec when the issue names one (`gh issue view N --json title,body`).
   - **Prompts.** Run `bun .claude/skills/code-review/scripts/prompts.ts`. It writes
     `REVIEW_DIR/prompts/round-1-<opus|codex>-all.md` and the report schema, and pins the diff to
     the merge base and the head.
   - **Launch both in one message**, after the gate is green and the journey is walked.
     - Opus: one Agent call, `subagent_type: opus-high`, `run_in_background: true`, prompt "Your whole brief is
       the file REVIEW_DIR/prompts/round-1-opus-all.md. Read it in full and follow it exactly."
     - Sol: one background Bash call:

       ```
       mkdir -p REVIEW_DIR/codex-runs
       codex exec -m gpt-6.1-sol -c model_reasoning_effort='"high"' -s read-only -C "$PWD" \
         --output-schema REVIEW_DIR/prompts/report.schema.json \
         -o REVIEW_DIR/round-1-codex-all.json --json - \
         < REVIEW_DIR/prompts/round-1-codex-all.md > REVIEW_DIR/codex-runs/all.jsonl 2>&1
       ```

       Read `"model"` and `"effort"` once, from the newest
       `~/.codex/sessions/<date>/rollout-*.jsonl`.
   - **Sol out of credits.** When `codex` is missing, will not start, or fails on a usage limit or
     quota (read the error in `codex-runs/all.jsonl`), do not wait or retry: delete any partial
     `round-1-codex-all.json`, review with Opus alone, and put this line in the disposition under
     the Review table: `Sol not run: <the error, in a few words>`. That line is how the owner
     tracks how often it happens.
   - **Join.** When every reviewer has replied, run
     `bun .claude/skills/code-review/scripts/join.ts`. It writes `REVIEW_DIR/round-1-joined.json`
     (read this one) and `round-1-joined.md` (for people). A nonzero exit names each invalid,
     unfinished or missing report: relaunch those fresh with the same prompt, then join again.
   - **Adjudicate** from `round-1-joined.json`, where every item sits under its file and line,
     lines in order:
     - A line whose `raised_in_lanes` holds both lanes needs no probe.
     - Check every other finding and every `to_verify` item in the code, or with a probe or a
       shot on the surface it names. Append the check and its result to `evidence.md`, and rate
       the item on that result.
     - Items on neighbouring lines of one file, and findings on different files, can be one
       defect. Merge them by failing case.

   Then write `REVIEW_DIR/round-1.md`:
   - One entry per distinct defect. The same defect from several reviewers keeps one id and names
     the others beside it, each with its lane ("Opus R1-M-01, Sol R1-S-02").
   - `high` first, then `medium` in reach order, at most eight, verbatim.
   - Re-rate as you join (standard, "What the loop fixes"):
     - a reviewer's `medium` whose failing case is not on a primary surface is a `low`;
     - a `low` that is a wrong word, label, number or language an owner or a customer reads on the
       normal path is a `medium`;
     - a `low` marked pre-existing is rated as if new when it sits in a file the branch changed, on a
       path it touched.
   - Join the lows by failing case; repeats sit on the same or neighbouring lines, and collapse to
     one id. `checked` items are never lows.
   - After the entries, add each `user` low whose fix is a few lines as `R1-L-01`… (standard, "Lows
     that ride along"). These do not count against the eight.

   Every other low, and every entry past the cap, goes to `REVIEW_DIR/deferred.md` as one line with
   its tag; the disposition reads it. No issue is filed. Done when `round-1.md` exists. Later rounds
   skip this step: `round-N.md` for N > 1 is the previous re-review's findings, renumbered.

2. **Fix round N** (standard, step 2). Spawn one agent, `subagent_type: opus-high`, with this prompt:

   ```
   You are the fix agent for review round N on branch <BRANCH> in <WORKTREE>. Land the fixes and
   leave them in the working tree: the orchestrator makes the round's single commit with your
   outcome lines as its body, and works alone, so spawn nothing.

   <findings>
   (REVIEW_DIR/round-N.md, verbatim and whole)
   </findings>

   <scope>
   Each fix is the smallest change that closes the failing case at the fix shape the finding
   names. No redesign, no new module, no moving a question to a new owner, no rewriting code
   the finding does not quote, and never a layout reshaped for a surface that is not primary
   (desktop 1024px and up, portrait phones 360 to 430px). Several findings with one cause take
   one small change. A fix that would need more than that is `deferred` with the reason. The
   round's fix diff stays smaller than the diff it fixes; if it is heading past that, stop
   and report which findings you did not take.
   </scope>

   <outcomes>
   (the "## Outcomes" section of docs/CODE_REVIEW.md, verbatim)
   </outcomes>

   <discipline>
   (the "## The fix round is an implementation" section of docs/CODE_REVIEW.md, verbatim, and
   the "### Machine" axis section for the self-check)
   </discipline>

   <instructions>
   Take the findings in id order. Before each edit, do the four things the discipline section
   names for that finding and write their result in one line under the finding in your report
   (blast radius files, the edge-input table, what the built artefact showed, the red test's
   name). Then close the failing case named in the finding, at the fix shape it names; when the
   finding is a `judgement` you disagree with, or the fix shape is wrong for a reason you can
   point at in the code, decline it with that reason. Add no comment; delete a comment your
   change makes wrong and leave every other comment to the comment cut. Deliver exactly the fixes; every other
   improvement you notice goes into a "Noticed, not changed" list at the end of your report.
   When all fixes are in, walk the Machine questions over `git diff` of your own changes and fix
   what they find before the gate. Run `MIX_TEST_PARTITION=_fix_$$ mix precommit` once at the
   end and paste its tail. Write the outcome lines, one per finding id, into
   REVIEW_DIR/round-N-outcomes.md, then reply with that path and the precommit tail.
   </instructions>
   ```

   Read the outcomes file: every id in `round-N.md` has a line, or the round is not done (relaunch
   for the missing ids). Measure `git diff --shortstat` of the working tree against the round's
   start; a fix diff larger than the branch diff is reverted to the fixes that stay small, and
   the rest are deferred. Commit: subject `Review round N: <x> fixed, <y> deferred`, body = two to
   four plain bullets on what changed (the `pr` skill's commit shape; the outcome lines stay in
   `REVIEW_DIR`). Record the commit sha as the round's end. Then run the round's gates on it and
   append the results to `REVIEW_DIR/evidence.md`: `MIX_TEST_PARTITION=_review_N_$$ mix precommit`,
   the specs the round touched on an isolated stack, and shots of anything the round changed on
   screen, each with a one-line reading. The re-review below reads that file; the PR body, the
   shots and the suite are a checklist in it, never findings.

3. **Re-review round N** (standard, step 3). Opus alone. Measure the fix diff first:
   `git diff --shortstat <round start>...<round end>`. Then spawn two agents in one message, both
   `subagent_type: opus-high`, `run_in_background: true`:
   - **The verifier.** Its prompt:
     "You are the verifier of review round N on branch <BRANCH> in <WORKTREE>. Read the code and
     run git reads only; edit nothing and spawn nothing. The findings are REVIEW_DIR/round-N.md,
     the outcomes REVIEW_DIR/round-N-outcomes.md, and the fix is `git diff <round start>...<round
     end>`. For every outcome line, open the code and answer closed, partly or not closed. A
     `fixed` must close the failing case named in the finding, not its label. A `declined` or
     `deferred` reason must be true in the code. Write a table of every id, with your verdict
     and one line of evidence, to REVIEW_DIR/round-N-verify.md, then reply with only the path and
     the verdict counts."
   - **Fresh eyes.** Build its prompt with
     `prompts.ts --round <N+1> --range <round start>...<round end> --lanes opus`. It reads the fix
     diff as new code and writes `REVIEW_DIR/round-<N+1>-opus-all.json`. Then run
     `join.ts --round <N+1>`.
   From `round-<N+1>-joined.json`, write `round-N-rereview.md`: one entry per distinct defect (the
   same defect seen by two reviewers is one entry with both sources named), re-rated by the tiers as
   in step 1, and append the verifier's `partly` and `not closed` rows as entries under their
   original failing case. The entry count is the round's count. After round 1: every `high` or
   `medium` entry and every re-entered row becomes `round-2.md` (ids `R2-…`), at most eight, and
   you go to step 2. After round 2: only `high` entries and re-entered rows become `round-3.md`;
   there is no round 3 for a `medium`. Handle the re-review's `to_verify` items and lows as in
   step 1: small `user` lows ride into that next round as `R2-L-…` (or `R3-L-…`);
   every other low, and every low when no next round runs, is one line in `deferred.md`.
   Done when the joined report holds nothing above `low` and every verdict is `closed`.
   **Round cap: two fix rounds** (a third only for `high`). After the cap, every entry still above
   `low` goes into `disposition.md` under "Open at hand-over" for the owner's word.

4. **Comment cut** (standard, step 4). Once, after the last fix round lands (after round 1 when
   no fix round ran), never beside an agent still editing the same files. Record the start sha,
   then spawn one agent, `subagent_type: opus-high`, with this prompt:

   ```
   You are the comment-cut agent for branch <BRANCH> in <WORKTREE>. Change comments only: doc
   strings, moduledocs, code comments, spec and test headers. Leave the edits in the working
   tree; the orchestrator commits them. Spawn nothing.

   <files>
   (git diff --name-only refs/remotes/origin/main...HEAD, one per line)
   </files>

   <bar>
   (the "## Comments" section of DEVELOPMENT.md, verbatim)
   </bar>

   <protected>
   Keep as they are: the reason on a lint or safety guard's disable comment, the one-sentence
   moduledoc Credo requires, and this doc text the spec requires:
   (the lines, or "none")
   </protected>

   <instructions>
   Read each file whole. Delete every comment that says what, how much, where or what used to
   be, and every comment that disagrees with the code below it; deleting beats shortening. A
   genuine why (a platform limit, a browser or focus quirk, a product decision with its issue)
   stays, cut to one or two sentences. Leave a file the branch barely touched alone unless its
   comment share rose against the merge base. Write a table to REVIEW_DIR/comment-cut.md: each
   file, its comment share at `git merge-base refs/remotes/origin/main HEAD` and now. Reply with
   the path and the number of lines removed.
   </instructions>
   ```

   Read every deleted line (`git diff`): code among them, a protected line or a genuine why
   goes back. No file's share may be above its merge-base share. Commit: subject `Comment cut:
   <n> lines removed`, and append the share table to `REVIEW_DIR/evidence.md`. Done when the
   commit exists and the table shows no share higher than at the merge base.

5. **Evidence** (standard, step 5). Run the full gate yourself: `mix precommit` on a partition; the
   browser journey tests the standard's step 5 names, when the branch changed a screen (a test
   that fails under load and passes alone is a flake, note it); `ux-check` when anything renders. Done when
   `REVIEW_DIR/evidence.md` names each gate with its result and each `did not finish` line from
   any round with what was rerun.

6. **Hand over** (standard, step 6). No issue is filed for what the loop did not fix. Write
   `REVIEW_DIR/disposition.md` in the shape the standard's "The disposition" section shows: the
   Review table (every `high`, `medium` and riding `L` id across rounds with severity, outcome and
   commit, then `reviewed at <head> after rebase onto <main sha>`, the rerun lines, the `Sol not run:` line when it applies, the `Dropped:
   <n> distinct lows (<count per tag>). Open at hand-over: <ids>` line, read from
   `deferred.md`, with every deferred `medium` also under "Open at hand-over", and the `Seen, not
   fixed:` line for out-of-scope defects older than the branch), and the Behavior notes (from the
   Spec sections: each behaviour
   deliberately changed, or `none`). Tell the user the rounds run, the counts, the entries open at
   hand-over, and the declined `high` findings that need their word; `implement` then asks their
   approval and opens the PR with the `pr` skill. Done when `disposition.md` has a row per `high`,
   `medium` and riding `L` id.

## Completion

Every id in `REVIEW_DIR/round-*.md` has an outcome, the last re-review holds nothing above `low` (or
the round cap was reached and every remaining entry above `low` is under "Open at hand-over"), every
line of `deferred.md` is on the disposition, the comment cut is committed after the last fix round,
the gate is green on the rebased head, and
`disposition.md` exists. If any of those is false, the review is not done; say which.
