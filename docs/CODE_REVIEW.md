# Code review

One standard for every review of code in this repo: run by the `code-review` skill, inside the
`implement` skill, or by an agent with no skill at all. Follow the loop and write findings in the
finding format. Each reviewer holds the axis lists it was given and rates every finding by reach.

Why the loop has this shape. Reviews that read only the diff miss the defects a user meets on the
real journey; branches nobody read as a whole hide half of what review bots later report; and
fixes that nobody re-reads produce most of the next round's bugs.

## What the loop fixes

The loop exists to stop defects a real user would meet. It is not a place to polish. Every
finding is rated by **consequence times reach**, and the rating decides its fate before any
agent touches code:

- **`high`, a blocker.** Cannot ship: a Game or Room state lost or corrupted, hidden dice shown to
  anyone but their owner, a security hole, the primary path broken on a primary surface, the game
  unplayable. Always fixed.
- **`medium`, fix now.** Wrong behaviour that a typical user meets on a **primary surface** and
  would notice as worse. Primary surfaces are desktop at 1024px and up, portrait phones 360 to
  430px wide, every seat at the table (the Player on turn, another Player, a Spectator, the Host),
  a return after being Away, and a reload. A wrong word, label or number that a Player reads on
  the normal path is at least `medium`, never `low`; so is a word that breaks the glossary in
  `CONTEXT.md`. Fixed in the round, up to the cap.
- **`low`, fixed only when it rides along.** Everything else, tagged by who meets it: `user` when
  a person using the product can see it (fringe viewports such as landscape phones, under 360px or
  zoomed; sub-second races such as a double tap); `code` for structure, naming, duplication, a
  missing test that hides no known bug; `process` for the PR body, evidence paperwork and document
  consistency. A low that does not ride along is dropped: one line in the disposition, no issue
  filed.

**Comments are not reviewed.** No reviewer raises a finding about a code comment, doc string or
test header, whether it is below the bar or out of date. The comment cut (step 4) owns them: it
runs once, after the last fix round, over every file the branch touched, and would delete most of
what a comment finding had a fix agent rewrite.

**Unverified is not a severity.** A primary-surface suspicion the code cannot confirm (a second
tap on a phone, a LiveView that does not rejoin after the Room restarts) goes to the orchestrator,
who checks it with a probe, a shot or a test and rates it on the result, never drops it as
unverified.

**Older than the branch.** A defect that predates the branch is rated as if new when it sits in a
file the branch changed, on a path the branch touched. Anywhere else the disposition names it as
seen, not fixed.

**Lows that ride along**, decided per item. A `user` low whose fix is small (a few lines, no new
module, no new test layer) rides along in any fix round that runs; it does not count against the
cap of eight, and is dropped when its fix outgrows that. `code` and `process` lows never ride
along. No round ever runs for lows alone: a report with nothing above `low` ends the loop. A low
that argues with a decision the owner has on record is dropped, never fixed. Lows filed as debt
issues pile up unread, and a list of twenty structure lows buries the four a user would see.

## The loop

Every round ends in one commit. A pull request opens when the last re-review reported nothing
above `low`, or when the round cap was reached and what is left is on the record.

**The caps.** A fix round takes at most eight findings above `low`, `high` first, then `medium`
by reach. **The round cap is two**: round 2 takes `high` only. A `medium` past either cap is
listed in the disposition under "Open at hand-over" for the owner's word. A guard that has
produced findings in every round is deleted rather than patched again.

0. **Base and journey.** `git fetch origin && git rebase refs/remotes/origin/main`, resolve
   conflicts, `mix precommit` green, so reviewers read the diff that will merge. Every command
   spells the remote-tracking ref in full: a local branch named `origin/main` shadows the bare
   form, and a rebase onto it is a no-op that looks like success. Then the orchestrator walks the
   real journey the branch changes, from a fresh Room, with a second Player in another browser
   when the journey has more than one seat, and through a reload where the journey has one, and
   records each shot with a one-line reading in `notes/reviews/<branch>/evidence.md`. A diff
   reader cannot see what the other seat sees; the walk can. Done when
   `git merge-base --is-ancestor refs/remotes/origin/main HEAD` holds, the gate is green, and
   `evidence.md` holds the journey or one line saying no user journey passes through the branch.
1. **Review round 1.** Two reviewers run at once on the same prompt, each holding all four axis
   lists and reading the diff pinned to the merge base and head: one Opus sub-agent, and one Codex
   `gpt-6.1-sol` run at high effort. Two models find about as many true mediums each, and together
   about half as many again as either alone. When Codex has no credits left, Opus reviews alone,
   and the disposition says so. Each reviewer writes a JSON report (the finding format below, as
   JSON) to `notes/reviews/<branch>/round-1-<lane>-all.json`. A script joins the reports: it
   validates each one, numbers its items, and files every item under its file and line, lines in
   order, so repeats and neighbours sit together. The orchestrator reads that joined file, not the
   reports. A line both lanes raised as `medium` or `high` needs no probe; every other finding and
   every `to_verify` item is checked in the code or with a probe and rated on the result. Then it
   writes `round-1.md`: one entry per distinct defect (the same defect from two reviewers is one
   id, the others named beside it), `high` first, at most eight, in reach order, then the riding
   `user` lows as `R1-L-01`…. Lows are joined by failing case, so duplicates collapse to one id,
   and only distinct ids are counted. This step runs once: later rounds start at step 2 from the
   re-review's findings. Done when the join reports no invalid, unfinished or missing report.
2. **Fix round N.** One fix agent receives that file whole, never a summary of it. It writes one
   outcome line per finding (see Outcomes) and lands the fixes with the gate green. Each fix is
   the smallest change that closes the failing case at the fix shape the finding names: no
   redesign, no new module, no moving a question to a new owner unless the fix shape says so,
   and never a layout reshaped for a surface that is not primary. A fix that would need one of
   those is `deferred` with that reason and goes to "Open at hand-over"; the round's fix diff stays
   smaller than the diff it fixes. Done when every finding id in the file has an outcome. Commit
   as `Review round N: <fixed> fixed, <declined> declined` with two to four plain bullets naming
   what changed; the outcome lines reach the pull request through the disposition. Then, before the
   re-review, the orchestrator runs the round's gates on the new head: `mix precommit` on a
   partition, the touched tests, and shots of anything the round changed on screen, recorded in
   `notes/reviews/<branch>/evidence.md`. The re-review reads that record. The PR body, the
   shots and the suite are one checklist there, never findings.
3. **Re-review round N.** Two jobs on Opus alone, sized by the fix diff (the round's commit range). A
   **verifier** walks every outcome line: for each `fixed` it confirms the failing case is closed,
   not relabelled; for each `declined` or `deferred` it confirms the reason is true in the code.
   **Fresh eyes** read the fix diff as new code with the question lists: one reviewer holding all
   four lists.
   The orchestrator joins the reports into one, one entry per distinct defect (the same defect
   seen by two reviewers is one entry with both sources named), rated by the same reach rule, and
   that count is the round's count. Entries of `high`, and every outcome the verifier judged
   `partly` or `not closed`, start round N+1 at step 2 with that file, up to the round cap; a
   `medium` found by a re-review joins round N+1 only when round N+1 is round 2 and the cap of
   eight leaves room. A `user` low rides along into round N+1 by "Lows that ride along"; when no
   round N+1 runs, every low is dropped. Done when the joined report
   holds nothing above `low` and every outcome is `closed`, or the cap is reached and every
   remaining entry above `low` is on the record.
4. **Comment cut.** Once, after the last fix round (after round 1 when no fix round ran), one
   agent on Opus reads every file in `git diff --name-only refs/remotes/origin/main...HEAD` whole
   and holds each comment, doc string and test header against DEVELOPMENT.md, "Comments". A
   comment that says what, how much, where or what used to be is deleted, and so is one that
   disagrees with the code; deleting beats shortening. A genuine why (a platform limit, a browser
   or focus quirk, a product decision with its issue) stays, cut to one or two sentences. Kept
   as they are: doc text the spec requires, the reason on a guard's disable comment and the
   one-sentence moduledoc Credo requires. A file the branch barely touched is left alone unless
   its comment share rose. The cut changes comments only, and lands as its own commit,
   `Comment cut: <n> lines removed`. Done when the orchestrator has read every deleted line and
   found no code among them, and `evidence.md` holds each touched file's comment share at the
   merge base and after the cut, none higher.
5. **Evidence.** The full local gate: `mix precommit`; when the branch changed a screen, the
   browser journey tests that cover the screens it touched; `ux-check` shots when anything
   renders. A reviewer or fix agent that stopped early (rate limit, crash) is rerun first,
   because from outside a half-run review looks exactly like a clean one. Done when
   `notes/reviews/<branch>/evidence.md` names each gate with its result and each `did not finish`
   with what was rerun.
6. **Pull request.** `notes/reviews/<branch>/disposition.md` holds the disposition (see below) and
   the Behavior notes; the table goes into the PR's Review section, the notes into its Summary. The pull request is ready to merge when it opens.
   Review bots are extra eyes when credits allow; their prose verdicts get replies like threads do.
   Done when `disposition.md` has a row per finding id and the template is filled from it.

## What every reviewer receives

- the diff command and `git log --oneline` of the range
- the issue (the spec) and the PR body, with its screenshot paths
- the journey record from step 0 in `evidence.md`: the shots and their one-line readings
- the blast radius: for each function, message, assign, column or key the diff changes, the files
  that use it (`git grep -ln <name>`), so "who else depends on this" is a list, not a guess
- the four axis sections from this document, pasted whole, and the finding format
- the reach rule and the primary surfaces from "What the loop fixes", so severity is rated the
  same way by every reviewer
- these rules: read the whole diff; open any file a hunk's correctness depends on; quote the code
  before judging it; write up only `high` and `medium` findings and give everything else the
  one-line forms in the finding format, because a written-up low costs a fix agent's attention
  and a reviewer's tokens for a case nobody will meet; make the report file your whole output,
  and read and judge the diff in your own session, because a sub-agent's summary loses the quoted
  lines a finding needs.

## The finding format

```
### R1-M-03 · high · lib/three_sixes/room/server.ex:142
Failing case: the Player on turn Raises while the Host-handover timer fires; the timer's handler
works from the state it read before the Raise and passes the turn on, so the Raise is lost.
Evidence: server.ex:138-150 reads state.turn, then schedules handover from that copy;
handle_call(:raise, ...) at :96 updates state.turn without cancelling the timer.
Rule: judgement (one message at a time only helps when every handler reads the current state).
Fix shape: cancel the handover timer in the Raise handler, as the Check handler at :120 does.
```

- **Id** is `R<round>-<axis>-<n>`: `S` spec, `T` standards, `M` machine, `E` evidence. Ids never
  change once written; the fix round and the PR refer to them.
- **Reviewer reports are JSON** with the same parts, one item per finding, low, to-verify line and
  checked line; the orchestrator's `round-N.md` stays in this markdown. The join assigns the ids
  (`A` for an all-axes reviewer, which is what round 1 runs), and two lanes share ids, so a
  source is always named with its lane: "Opus R1-A-01".
- **Severity by consequence times reach**, as "What the loop fixes" defines it: `high` is a
  blocker; `medium` is wrong behaviour a typical user meets on a primary surface and would notice
  as worse; `low` is everything else. Comments get no finding at any severity.
- **The report's other headings**, after the findings, one line per item:
  `## Deferred` holds the lows as `R1-M-L2 · user · lib/three_sixes_web/live/room_live.ex:88 · on
  a landscape phone the Reaction bubble covers the seat name`, the tag from "What the loop fixes";
  `## To verify` holds each primary-surface suspicion the code cannot confirm, with the surface
  and the step that would show it; `## Checked` holds what was checked and found clean, which is
  never a Deferred line.
- **Failing case** is one concrete input or sequence, written so a test could be named after it.
- **Evidence** quotes the code by file and line, including the file outside the diff when that is
  where the truth is.
- **Rule** cites the document and the rule, or says `judgement`.
- **Fix shape** names the smallest change that closes the failing case; a fix that closes only the
  symptom (a new label for a wrong state) is not the fix shape.

<examples>
<example>
### R1-S-02 · medium · lib/three_sixes_web/live/room_live.ex:210
Failing case: a Player is Knocked out mid-Round; their screen still shows the Raise and Check buttons until the next Round starts.
Evidence: render/1 shows the action bar when @seat is set (room_live.ex:205-214); view_for/2 keeps the seat for a Knocked-out Player (room.ex:77) so their Placement shows.
Rule: CONTEXT.md, "Knocked out" (plays no further in the Game) and "Spectator".
Fix shape: show the action bar only when view_for/2 says the person is the Player on turn.
</example>
<example>
### R1-T-01 · low · lib/three_sixes/game/bid.ex:1
Failing case: none today; the next reader of "is this Bid a Raise" answers it here instead of in the rules core.
Evidence: Bid.higher?/2 repeats the comparison Rules.raise?/2 already owns (rules.ex:40).
Rule: judgement (one owner per question).
Fix shape: call Rules.raise?/2 and delete Bid.higher?/2.
</example>
<example>
### R2-E-01 · high · test/three_sixes/room/server_test.exs:40
Failing case: the R1-M-03 outcome says "fixed in a3b1c17c" but reverting the timer cancel leaves this test green, so the test does not prove the fix.
Evidence: the test sends the Raise and only then advances the clock past the handover; the failing case needs the timer message already in the mailbox.
Rule: docs/CODE_REVIEW.md, Evidence axis (a test that survives reverting the fix proves nothing).
Fix shape: send the timer message to the Room before the Raise and assert the turn did not pass.
</example>
</examples>

## The fix round is an implementation

A fix is new code written under more pressure and with less context than the code it replaces,
which is why later review rounds are mostly defects the fixes created: a CSS block nobody checked
in the built stylesheet, a pattern match with a new hole, an attribute swap that dropped the
visible state, a default flipped without the saved Rooms already holding the old value. So every
fix goes through the same discipline as the implementation, per finding, before the edit:

- **The smallest change.** The fix closes the failing case at the fix shape named and nothing
  else; several findings with one cause take one small change, not a reshaping.
- **Blast radius of the fix.** `git grep -ln` every function, message, key, column or selector
  the fix changes; each other reader or writer either still holds or is part of the fix.
- **Edge inputs of the new branch, as a table.** Empty, missing, the saved shape from before the
  change, the value that already exists, after a restore of the Room, every seat at the table.
- **The built artefact.** A change to CSS, a lint config, a lockfile or a bundle is checked in
  what the build emits, not in the source.
- **Red first.** The test that fails on the finding's case is written and run before the fix.
- **The Machine questions over the fix diff** before handing back, as a self-check.

Two rules about what a fix may add. **A fix adds no comment, and touches a document only when
the finding is about that document.** A comment the fix makes wrong is deleted, not corrected;
every other comment waits for the comment cut. Every sentence added is a claim the next reviewer
will test. **A guard is a parser or a behaviour test, never a regular expression over source**:
regex guards produce a new hole or a false positive every round. In this repo that means a Credo
check for Elixir.

## Outcomes

The fix agent writes one line per finding id in the round's outcomes file:

<example>
R1-M-03 fixed in 8f20915d
R1-S-02 fixed in 8f20915d
R1-T-01 declined: Bid.higher?/2 orders Bids for the history list, which Rules.raise?/2 does not answer (rules.ex:40 compares to the current Bid only)
R1-M-07 deferred: a layout reshaped for landscape phones, not a primary surface
</example>

A `declined` reason is one a reviewer can check against the code or a document. A fourth outcome,
`deferred: <reason>`, is for a finding whose fix would reshape a layout for a surface that is not
primary or would grow past the smallest change. A deferred `medium` is listed under "Open at
hand-over" for the owner, who decides whether it becomes an issue; a deferred `low` is dropped. A declined `high`
finding also needs the owner's word in the PR body. A finding with no outcome line is a finding the
fix round is not done with.

## The disposition

`notes/reviews/<branch>/disposition.md` is what the pull request carries. It has two sections,
pasted into the template's Review and Behavior notes sections:

<example>
## Review

| Finding | Severity | Outcome | Commit |
|---|---|---|---|
| R1-M-03 | high | fixed | 8f20915d |
| R1-S-02 | medium | fixed | 8f20915d |
| R1-T-01 | medium | declined: Bid.higher?/2 answers a question Rules.raise?/2 does not | |
| R1-E-05 | medium | deferred: a layout reshaped for landscape phones; open at hand-over | |
| R1-L-01 | low · user | fixed | 8f20915d |
| R2-E-01 | high | fixed | a3b1c17c |

reviewed at a3b1c17c after rebase onto c7ea2562
Round 1 Opus reviewer did not finish (rate limit); rerun, report complete.
Sol not run: usage limit reached.
Dropped: 14 distinct lows (9 code, 5 process). Open at hand-over: R1-E-05.
Seen, not fixed: room_live.ex:412 accepts a blank Nickname; older than this branch, on a path it does not touch.

## Behavior notes

- A Knocked-out Player now sees the table as a Spectator straight away, not at the next Round.
- none of the other behaviour changed on purpose.
</example>

## The four axes

Every reviewer holds all four axes. Questions carry the check that answers them, so a reviewer answers
from the code, not from impression.

### Spec

You check that what shipped is what was asked, no more and no less. Read the issue, the PR body or
implementer's report, and the diff.

- For every acceptance line in the issue: point at the hunk that delivers it, or report it as
  missing or partial with the line quoted.
- For every claim in the PR body or a commit message ("blocks", "always", "no longer"): point at the
  code that makes it true. A claim without code is a finding.
- For every deleted or replaced function (`git diff --diff-filter=D`, and hunks that remove a
  branch): say what it used to do and whether each behaviour is carried, intentionally dropped in
  the Behavior notes, or lost.
- Neighbours of the change. A change to what the product does has neighbours: the other places
  that show, predict or depend on the same fact. List them:
  - other views of the same fact: every seat's view of it (`view_for` per person), the Tally,
    Placements, anything that counts, summarises or repeats it;
  - what was made under the old behaviour: Rooms and Games saved before the change ships, open
    LiveViews that rejoin after the deploy;
  - other ways in: another seat, a Guest and an Account, another screen size, a reload, a return
    after being Away.

  Each neighbour is fixed in the same change, or named in the plan or PR with the reason it stays.
  A neighbour nobody named is a finding.
- Behaviour the issue did not ask for: name it, so the owner can keep or veto it.
- Product decisions on record (`docs/adr/`, `CONTEXT.md`, the issue's comments): a change that
  re-opens one is a finding even when the code is fine.
- The glossary: every user-facing word and every new name in code follows `CONTEXT.md`, including
  its _Avoid_ lists. A word on an _Avoid_ list on screen is a finding.

### Standards

You check this repo's own rules, the ones a generic reviewer cannot know. Always read `AGENTS.md`,
`DEVELOPMENT.md` and the ADRs in `docs/adr/`. Cite the document and the rule in every finding these
produce; a rule that is not written down is a `judgement` finding.

- One owner per question: for each new helper that reads, reshapes or interprets game state,
  `git grep` for an existing answerer. The rules core owns the rules; a second answer in a
  LiveView or the Room process is a finding even when it is correct.
- The pure core stays pure: the rules core takes state and returns state, with no processes,
  time, randomness or I/O of its own (ADR 0001).
- Smells (duplicated code, a helper that only delegates, a parameter for a need the spec lacks) are
  `judgement` findings; report each with the cost you can name.
- What a tool already enforces is not a finding: formatting, compiler warnings, Credo, and every
  check `mix precommit` runs.

### Machine

You read the program as the machine will run it, not as the author describes it. Open every file
a hunk depends on; the truth is usually outside the diff.

- One message at a time: the Room process handles one message at a time, so the races sit between
  messages. For every handler, ask what happens when another message lands first: a second
  Player's action, a timer firing, a LiveView going down, a save tick. A handler that acts on state
  read before a timer was scheduled, or a timer nobody cancels, is the race.
- Hidden information: for every field the diff adds to the Room or Game state, follow it through
  `view_for` to every seat. A Spectator, another Player or the page source seeing a die it should
  not is `high`.
- Restore: the Room saves every 5 s and on shutdown, never the Round's dice (ADR 0001). For every
  new field: is it saved, is it restored, and is it right after a restore voids the Round?
- Second writers: for every field, column, constant or key the diff constrains or changes, list
  every writer and reader from the blast radius. Each one satisfies the new rule or is a finding.
- Edge inputs as a table: for each new branch, write the cases down and answer each one.
  The cases: empty; `nil` or a missing key; the saved shape from before the change; the value that
  already exists; one Player left; the last die (the sixth); a Player who is Away; a Knocked-out
  Player; a Spectator; the Host leaving; the Room after a restore.
- Helpers: for each function the diff calls, open it and confirm it does what the call site
  assumes (does it reload the row, is it already inside a transaction, does it send a message or
  broadcast as a side effect).
- LiveView: for every event, the double submit (two taps before the reply) and the stale event
  from a page whose turn has passed; the server checks the turn, not the button's state. After a
  reconnect, the LiveView rejoins the Room and every assign comes from the Room, not from what the
  socket held.
- Migrations: they run against the database the running release is using.
- Third-party facts: for every assumed platform behaviour (Phoenix, LiveView, the browser, a
  library version), cite the documentation line or mark the assumption `unverified`.

### Evidence

You check that the proof is real. Read the tests, the PR body, the shots, and the
outcome lines of earlier rounds.

- Red then green: a bug fix has a test that fails on the code before the change; the report shows
  the red run, or the finding says it is missing.
- Tests assert behaviour: each branch has a case, including the mixed case that separates `some`
  from `every`; a test that would stay green with the fix reverted proves nothing.
- Layer: each new test sits in the layer DEVELOPMENT.md "Testing" assigns. A browser test for a
  rule the rules core or a LiveView test already pins is a finding.
- Two seats: a change to what one person sees is tested from at least two seats, so a leak to the
  other seat would fail the test.
- Layouts: one shot on each side of every breakpoint crossed, with the longest Nicknames; every
  shot has a one-line reading in the report.
- The gate: the precommit tail is in the report, pasted rather than linked (a path under `/tmp` is
  not evidence next week); the browser journey tests ran when the branch changed a screen, on the
  head that will merge, and the report names each file.
- Earlier rounds: every finding id has an outcome, and each `fixed` outcome names a commit whose
  diff closes the failing case.
- Dead agents: any step that did not finish is recorded, not silently absent.
