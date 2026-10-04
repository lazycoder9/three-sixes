// Joins one round's reviewer reports into round-<n>-joined.json (for the orchestrator) and
// round-<n>-joined.md (for people). It validates each report, numbers its items, stamps lane,
// model and axis from the file name, and files every item under its file and line, lines in
// order, so repeats and neighbours sit next to each other. It never decides that two items are
// one defect. A nonzero exit names the reports to rerun.
// Usage: bun .claude/skills/code-review/scripts/join.ts [review-dir] [--round N]
import { readdir } from "node:fs/promises";
import {
  AXES,
  LANES,
  SPLIT_AXES,
  type Axis,
  type Item,
  type Lane,
  type Report,
  fillAbsentNulls,
  reviewDir,
  validate,
} from "./report.ts";

const args = process.argv.slice(2);
const roundFlag = args.indexOf("--round");
const round = roundFlag >= 0 ? Number(args[roundFlag + 1]) : 1;
const dir = args.find((a, i) => !a.startsWith("--") && args[i - 1] !== "--round") ?? (await reviewDir());

type Entry = Item & { lane: Lane; model: string; axis: Axis; id: string };
type Line = { raised_in_lanes: Lane[]; items: Entry[] };

const reportName = new RegExp(`^round-${round}-(${Object.keys(LANES).join("|")})-(${Object.keys(AXES).join("|")})\\.json$`);
const names = (await readdir(dir)).filter((f) => reportName.test(f)).sort();

const invalid: { file: string; errors: string[] }[] = [];
const unfinished: { file: string; reason: string }[] = [];
const entries: Entry[] = [];
const checked: { lane: Lane; axis: Axis; text: string }[] = [];
const present = new Set<string>();

for (const name of names) {
  const [, lane, axis] = name.match(reportName)! as unknown as [string, Lane, Axis];
  let report: unknown;
  try {
    report = JSON.parse(await Bun.file(`${dir}/${name}`).text());
  } catch (e) {
    invalid.push({ file: name, errors: [`not JSON: ${(e as Error).message}`] });
    continue;
  }
  fillAbsentNulls(report);
  const errors = validate(report);
  if (errors.length) {
    invalid.push({ file: name, errors });
    continue;
  }
  present.add(`${lane}-${axis}`);
  const { items, finished, not_finished_reason } = report as Report;
  if (!finished) unfinished.push({ file: name, reason: not_finished_reason ?? "" });

  const letter = AXES[axis];
  const count = { finding: 0, low: 0, to_verify: 0 };
  const rank = (i: Item) => (i.kind === "finding" ? (i.severity === "high" ? 0 : 1) : 2);
  for (const item of [...items].sort((a, b) => rank(a) - rank(b))) {
    if (item.kind === "checked") {
      checked.push({ lane, axis, text: item.text });
      continue;
    }
    const id =
      item.kind === "finding"
        ? `R${round}-${letter}-${String(++count.finding).padStart(2, "0")}`
        : item.kind === "low"
          ? `R${round}-${letter}-L${++count.low}`
          : `R${round}-${letter}-V${++count.to_verify}`;
    const file = item.file?.replace(/^\.\//, "").trim() || null;
    entries.push({ ...item, file, lane, model: LANES[lane], axis, id });
  }
}

// A lane is whole with its four axis reports, or with the one reviewer that holds every axis.
const lanesPresent = [...new Set([...present].map((k) => k.split("-")[0] as Lane))];
const missing = lanesPresent.flatMap((lane) =>
  present.has(`${lane}-all`)
    ? []
    : SPLIT_AXES.filter((axis) => !present.has(`${lane}-${axis}`)).map((axis) => `round-${round}-${lane}-${axis}.json`),
);

const NO_FILE = "(no file)";
const NO_LINE = "none";
const weight = { high: 0, medium: 1 } as const;
const itemOrder = (e: Entry) => (e.kind === "finding" ? weight[e.severity!] : e.kind === "to_verify" ? 2 : 3);

const files: Record<string, Record<string, Line>> = {};
for (const e of entries) {
  const lines = (files[e.file ?? NO_FILE] ??= {});
  (lines[e.line === null ? NO_LINE : String(e.line)] ??= { raised_in_lanes: [], items: [] }).items.push(e);
}
for (const lines of Object.values(files))
  for (const line of Object.values(lines)) {
    line.items.sort((a, b) => itemOrder(a) - itemOrder(b) || a.lane.localeCompare(b.lane) || a.axis.localeCompare(b.axis));
    line.raised_in_lanes = [...new Set(line.items.filter((e) => e.kind === "finding").map((e) => e.lane))];
  }

// Files with a finding come first, then by name; lines ascend, with the line-less items last.
const fileOrder = Object.keys(files).sort((a, b) => {
  const top = (f: string) => Math.min(...Object.values(files[f]).flatMap((l) => l.items.map(itemOrder)));
  return top(a) - top(b) || a.localeCompare(b);
});
const lineOrder = (lines: Record<string, Line>) =>
  Object.keys(lines).sort((a, b) => (a === NO_LINE ? 1 : b === NO_LINE ? -1 : Number(a) - Number(b)));

const joined = {
  dir,
  round,
  lanes: Object.fromEntries(lanesPresent.map((l) => [l, LANES[l]])),
  problems: { invalid, unfinished, missing },
  counts: {
    findings: entries.filter((e) => e.kind === "finding").length,
    lines_raised_by_both_lanes: Object.values(files)
      .flatMap((lines) => Object.values(lines))
      .filter((l) => l.raised_in_lanes.length >= 2).length,
    lows: entries.filter((e) => e.kind === "low").length,
    to_verify: entries.filter((e) => e.kind === "to_verify").length,
  },
  // Arrays, not objects, so the order above survives JSON.
  files: fileOrder.map((file) => ({
    file,
    lines: lineOrder(files[file]).map((line) => ({ line, ...files[file][line] })),
  })),
  checked,
};

const label = (e: Entry) =>
  e.kind === "finding" ? `**${e.severity}**` : e.kind === "low" ? `low · ${e.tag}` : "to verify";
const md: string[] = [
  `# Round ${round}, joined (before adjudication)`,
  "",
  `Lanes: ${lanesPresent.map((l) => `${l} (${LANES[l]})`).join(", ")}. ${joined.counts.findings} findings, ` +
    `${joined.counts.lines_raised_by_both_lanes} lines raised by both lanes, ${joined.counts.lows} lows, ` +
    `${joined.counts.to_verify} to verify.`,
];
if (invalid.length || unfinished.length || missing.length) {
  md.push("", "## Rerun before adjudicating");
  for (const p of invalid) md.push(`- ${p.file} is invalid: ${p.errors.slice(0, 3).join("; ")}`);
  for (const p of unfinished) md.push(`- ${p.file} did not finish: ${p.reason}`);
  for (const f of missing) md.push(`- ${f} is missing`);
}
for (const { file, lines } of joined.files) {
  md.push("", `## ${file}`);
  for (const { line, raised_in_lanes, items } of lines) {
    const both = raised_in_lanes.length >= 2 ? " · raised by both lanes" : "";
    md.push(`- **${line === NO_LINE ? "no line" : `:${line}`}**${both}`);
    for (const e of items) {
      md.push(`  - ${e.lane} ${e.axis} ${e.id} (${label(e)}) ${e.text}`);
      if (e.fix_shape) md.push(`    Fix shape: ${e.fix_shape}`);
      if (e.surface_step) md.push(`    To verify: ${e.surface_step}`);
    }
  }
}

await Bun.write(`${dir}/round-${round}-joined.json`, JSON.stringify(joined, null, 2) + "\n");
await Bun.write(`${dir}/round-${round}-joined.md`, md.join("\n") + "\n");

console.log(
  `${names.length} reports → ${joined.counts.findings} findings, ${joined.counts.lows} lows, ` +
    `${joined.counts.to_verify} to verify across ${joined.files.length} files → ${dir}/round-${round}-joined.{json,md}`,
);
if (invalid.length || unfinished.length || missing.length) {
  console.log(`rerun: ${[...invalid.map((p) => p.file), ...unfinished.map((p) => p.file), ...missing].join(", ")}`);
  process.exit(1);
}
