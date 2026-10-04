// Builds reviewer prompts from docs/CODE_REVIEW.md: one per lane, each holding all four axes. The
// lanes' prompts differ only in the line that says where the report goes.
// Usage, from the worktree root once REVIEW_DIR holds base.md, issue.md and evidence.md:
//   bun .claude/skills/code-review/scripts/prompts.ts [--round N --range A...B]
//     [--lanes opus,codex] [--root <snapshot worktree>]
// --round/--range build a re-review: the fix diff A...B read as new code. --root points the
// reviewers at another worktree (a frozen copy of the branch) with a copy of evidence.md, so a
// later run reads what round 1 read.
import { realpathSync } from "node:fs";
import { LANES, SPLIT_AXES, reportSchema, reviewDir, type Axis, type Lane } from "./report.ts";

const args = process.argv.slice(2);
const flag = (name: string) => (args.includes(name) ? args[args.indexOf(name) + 1] : undefined);
const rootFlag = args.indexOf("--root");
const round = Number(flag("--round") ?? 1);
const range = flag("--range");
const lanes = (flag("--lanes")?.split(",") ?? Object.keys(LANES)) as Lane[];

const root = (await Bun.$`git rev-parse --show-toplevel`.text()).trim();
const dir = realpathSync(await reviewDir());
const reviewRoot = rootFlag >= 0 ? realpathSync(args[rootFlag + 1]) : root;
const standard = await Bun.file(`${root}/docs/CODE_REVIEW.md`).text();

function section(heading: string): string {
  const lines = standard.split("\n");
  const start = lines.findIndex((l) => l === heading);
  if (start < 0) throw new Error(`docs/CODE_REVIEW.md has no "${heading}"`);
  const level = heading.match(/^#+/)![0].length;
  let end = lines.length;
  for (let i = start + 1; i < lines.length; i++) {
    const m = lines[i].match(/^(#+) /);
    if (m && m[1].length <= level) {
      end = i;
      break;
    }
  }
  return lines.slice(start, end).join("\n").trim();
}

// The diff is pinned to shas, so a reviewer who starts late still reads the branch round 1 read.
async function pinnedBase(): Promise<string> {
  const text = await Bun.file(`${dir}/base.md`).text();
  const head = (await Bun.$`git -C ${reviewRoot} rev-parse HEAD`.text()).trim();
  const mergeBase = (await Bun.$`git -C ${reviewRoot} merge-base refs/remotes/origin/main HEAD`.text()).trim();
  const pinned = text.replaceAll("refs/remotes/origin/main...HEAD", `${mergeBase}...${head}`);
  return range ? `${pinned}\nThis is a re-review. Read only the fix diff \`git diff ${range}\` as new code.\n` : pinned;
}

const title = (axis: string) => axis[0].toUpperCase() + axis.slice(1);
const base = await pinnedBase();
const issue = await Bun.file(`${dir}/issue.md`).text();
const schemaPath = `${dir}/prompts/report.schema.json`;
const evidencePath = rootFlag >= 0 ? `${dir}/evidence-round-${round}.md` : `${dir}/evidence.md`;
const prBody = (await Bun.file(`${dir}/pr-body.md`).exists()) ? `${dir}/pr-body.md` : "none yet";

await Bun.write(schemaPath, JSON.stringify(reportSchema, null, 2) + "\n");
if (rootFlag >= 0) await Bun.write(evidencePath, Bun.file(`${dir}/evidence.md`));

const tiers = section("## What the loop fixes");
const format = section("## The finding format");
const jsonShape = `The report is one JSON object in the shape of ${schemaPath}: \`{"items": [...], "finished": true, "not_finished_reason": null}\`. Every item carries every key; a key that does not apply is \`null\`. The format section above says what each part means; in JSON:
- a high or medium finding is \`kind: "finding"\` with \`severity\`, \`file\` and \`line\` (the heading's location), \`text\` (the failing case), \`evidence\`, \`rule\` and \`fix_shape\`;
- a low is \`kind: "low"\` with \`tag\` (user, code or process), \`file\`, \`line\` and \`text\` (the failing case in one clause);
- a primary-surface suspicion you cannot confirm from the code is \`kind: "to_verify"\`, unrated, with \`text\` (the suspicion), \`surface_step\` (the surface and the step that would show it) and \`file\`/\`line\` when one is involved;
- what you checked and found clean is \`kind: "checked"\`, \`text\` only, one item per check.
Do not write ids: the join numbers the items in your order, findings by severity first. \`file\` is a repo-relative path without the line; the line goes in \`line\`.`;

const axis: Axis = "all";
const heading = "ALL-AXES";
const axisText = SPLIT_AXES.map((a) => section(`### ${title(a)}`)).join("\n\n");

for (const lane of lanes) {
  const out = `${dir}/round-${round}-${lane}-${axis}.json`;
  const delivery =
    lane === "opus"
      ? `Write the JSON report to ${out}, then reply with only the path and the item counts.`
      : `You run in a read-only sandbox, so do not try to write files: your final message IS the JSON report (the CLI checks it against the schema and saves it to ${out}).`;

  const prompt = `You are the ${heading} reviewer for one branch of the Three Sixes repo (Phoenix + LiveView), in the git worktree ${reviewRoot}.
Your whole output is one report. Read the code and run git reads only, in this session, because the fix round owns every change and a sub-agent's summary loses the lines a finding quotes. Do not edit any file, do not run mix, bun or any test suite (other processes use this tree), and spawn no sub-agents.

<context>
Branch, head, diff command, commits and blast radius:
${base}

Spec (the GitHub issue):
${issue}

Plan and implementer reports: ${dir}/plan.md and every *-report.md in ${dir} (read the ones that exist)
PR body: ${prBody}
Journey: ${evidencePath} (the orchestrator's walk of the real journey, each shot with a one-line reading; shots are the image paths it names)
</context>

<tiers>
${tiers}
</tiers>

<axis>
${axisText}
</axis>

<format>
${format}

${jsonShape}
</format>

<instructions>
Read the whole diff, then open every file a hunk depends on and quote the lines that decide the answer before you judge. Walk your axis's questions one by one over the diff. For each answer that is a defect, rate it by the tiers section: a \`high\` or \`medium\` is a finding; a \`low\` is a low item and nothing more. A case a typical user will not meet on a primary surface is \`low\` however wrong the code is. Comments, doc strings and test headers get no item at any severity: the comment cut owns them. When you run out of questions, scan once more for anything the questions did not name.
If you cannot finish, set \`finished\` to false and say why in \`not_finished_reason\`, so the orchestrator can rerun you instead of reading silence as a clean report.
${delivery}
</instructions>
`;
  await Bun.write(`${dir}/prompts/round-${round}-${lane}-${axis}.md`, prompt);
}

console.log(`${lanes.length} round ${round} prompts written to ${dir}/prompts (${lanes.join(", ")})`);
