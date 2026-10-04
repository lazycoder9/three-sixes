// What round 1's reviewer reports share: the lanes, the axes, and the JSON shape of one report.
// prompts.ts writes the schema for `codex exec --output-schema`; join.ts validates every report
// against the same object, because nothing enforces the shape on an Opus sub-agent.

export const LANES = { opus: "claude-opus-5-5", codex: "gpt-6.1-sol" } as const;
export type Lane = keyof typeof LANES;

// "all" is the reviewer round 1 runs per lane, holding every axis; join.ts still reads one-axis reports.
export const AXES = { spec: "S", standards: "T", machine: "M", evidence: "E", all: "A" } as const;
export type Axis = keyof typeof AXES;
export const SPLIT_AXES: Axis[] = ["spec", "standards", "machine", "evidence"];

type Schema = Record<string, unknown>;
const str: Schema = { type: "string" };
const maybeStr: Schema = { type: ["string", "null"] };
const maybeEnum = (values: string[]): Schema => ({
  anyOf: [{ type: "string", enum: values }, { type: "null" }],
});

// Strict-mode shape (every key required, nulls instead of absent keys), which Codex needs.
export const reportSchema: Schema = {
  type: "object",
  additionalProperties: false,
  required: ["items", "finished", "not_finished_reason"],
  properties: {
    items: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: [
          "kind",
          "severity",
          "tag",
          "file",
          "line",
          "text",
          "evidence",
          "rule",
          "fix_shape",
          "surface_step",
        ],
        properties: {
          kind: { type: "string", enum: ["finding", "low", "to_verify", "checked"] },
          severity: maybeEnum(["high", "medium"]),
          tag: maybeEnum(["user", "code", "process"]),
          file: maybeStr,
          line: { type: ["integer", "null"] },
          text: str,
          evidence: maybeStr,
          rule: maybeStr,
          fix_shape: maybeStr,
          surface_step: maybeStr,
        },
      },
    },
    finished: { type: "boolean" },
    not_finished_reason: maybeStr,
  },
};

export type Item = {
  kind: "finding" | "low" | "to_verify" | "checked";
  severity: "high" | "medium" | null;
  tag: "user" | "code" | "process" | null;
  file: string | null;
  line: number | null;
  text: string;
  evidence: string | null;
  rule: string | null;
  fix_shape: string | null;
  surface_step: string | null;
};
export type Report = { items: Item[]; finished: boolean; not_finished_reason: string | null };

function typeOf(v: unknown): string {
  if (v === null) return "null";
  if (Array.isArray(v)) return "array";
  if (typeof v === "number") return Number.isInteger(v) ? "integer" : "number";
  return typeof v;
}

function check(v: unknown, s: Schema, path: string, errors: string[]): void {
  if (s.anyOf) {
    const ok = (s.anyOf as Schema[]).some((alt) => {
      const e: string[] = [];
      check(v, alt, path, e);
      return e.length === 0;
    });
    if (!ok) errors.push(`${path}: ${JSON.stringify(v)} matches no allowed form`);
    return;
  }
  const types = ([] as string[]).concat((s.type as string | string[]) ?? []);
  if (types.length && !types.includes(typeOf(v))) {
    errors.push(`${path}: expected ${types.join("|")}, got ${typeOf(v)}`);
    return;
  }
  if (s.enum && !(s.enum as unknown[]).includes(v)) errors.push(`${path}: ${JSON.stringify(v)} not in enum`);
  if (typeOf(v) === "object" && s.properties) {
    const obj = v as Record<string, unknown>;
    const props = s.properties as Record<string, Schema>;
    for (const key of (s.required as string[]) ?? []) if (!(key in obj)) errors.push(`${path}.${key}: missing`);
    for (const [key, val] of Object.entries(obj)) {
      if (props[key]) check(val, props[key], `${path}.${key}`, errors);
      else if (s.additionalProperties === false) errors.push(`${path}.${key}: unexpected key`);
    }
  }
  if (typeOf(v) === "array" && s.items)
    (v as unknown[]).forEach((x, i) => check(x, s.items as Schema, `${path}[${i}]`, errors));
}

// Opus sub-agents often leave nullable keys off `checked` items; an absent key and a null mean the
// same, and rejecting the report cost a ~100k-token rerun in three of four sessions.
export function fillAbsentNulls(value: unknown): void {
  const items = (value as { items?: unknown })?.items;
  if (!Array.isArray(items)) return;
  const props = (reportSchema.properties as Record<string, Schema>).items.items as Schema;
  const nullable = Object.entries(props.properties as Record<string, Schema>)
    .filter(([, s]) => JSON.stringify(s).includes('"null"'))
    .map(([key]) => key);
  for (const item of items)
    if (typeOf(item) === "object")
      for (const key of nullable) if (!(key in (item as object))) (item as Record<string, unknown>)[key] = null;
}

// The schema checks the shape; these rules check that each kind carries what the standard asks of it.
export function validate(value: unknown): string[] {
  const errors: string[] = [];
  check(value, reportSchema, "$", errors);
  if (errors.length) return errors;
  const report = value as Report;
  report.items.forEach((item, i) => {
    const at = `$.items[${i}]`;
    if (item.kind === "finding") {
      if (!item.severity) errors.push(`${at}: a finding needs severity`);
      for (const key of ["file", "evidence", "rule", "fix_shape"] as const)
        if (!item[key]) errors.push(`${at}: a finding needs ${key}`);
    }
    if (item.kind === "low" && !item.tag) errors.push(`${at}: a low needs a tag`);
    if (item.kind === "to_verify" && !item.surface_step) errors.push(`${at}: a to_verify item needs surface_step`);
  });
  if (!report.finished && !report.not_finished_reason) errors.push("$: not finished, and no reason given");
  return errors;
}

export async function reviewDir(): Promise<string> {
  const root = (await Bun.$`git rev-parse --show-toplevel`.text()).trim();
  const branch = (await Bun.$`git branch --show-current`.text()).trim();
  return `${root}/notes/reviews/${branch}`;
}
