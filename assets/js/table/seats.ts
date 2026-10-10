export type Point = [x: number, y: number];

export type Layout = "ring" | "long" | "arc";

export type Table = {
  seats: number;
  seated: boolean;
  layout: Layout;
  width: number;
  height: number;
  seatWidth: number;
  seatHeight: number;
};

const STEPS = 720;

function ellipse(n: number, ratio: number): Point[] {
  const angle = (i: number) => Math.PI / 2 + (i / STEPS) * 2 * Math.PI;
  const travelled = [0];
  for (let i = 1; i <= STEPS; i++) {
    const dx = ratio * (Math.cos(angle(i)) - Math.cos(angle(i - 1)));
    const dy = Math.sin(angle(i)) - Math.sin(angle(i - 1));
    travelled.push(travelled[i - 1] + Math.hypot(dx, dy));
  }
  const edge = travelled[STEPS];
  return Array.from({ length: n }, (_, k) => {
    const goal = (k / n) * edge;
    const i = Math.max(
      1,
      travelled.findIndex((d) => d >= goal),
    );
    const t = angle(i - 1 + (goal - travelled[i - 1]) / (travelled[i] - travelled[i - 1]));
    return [Math.cos(t), Math.sin(t)];
  });
}

function longTable(n: number, a: number, b: number): Point[] {
  if (a <= 1.3 * b) return ellipse(n, a / b);
  const side = a - b;
  const end = Math.PI * b;
  const edge = 4 * side + 2 * end;
  return Array.from({ length: n }, (_, k): Point => {
    let d = (k / n) * edge;
    if (d < side) return [-d / a, 1];
    d -= side;
    if (d < end) return [(-side - b * Math.sin(d / b)) / a, Math.cos(d / b)];
    d -= end;
    if (d < 2 * side) return [(d - side) / a, -1];
    d -= 2 * side;
    if (d < end) return [(side + b * Math.sin(d / b)) / a, -Math.cos(d / b)];
    return [(side - (d - end)) / a, 1];
  });
}

function arc(n: number): Point[] {
  const spread = Math.min(50, 150 / Math.max(1, n - 1));
  return Array.from({ length: n }, (_, k) => {
    const t = ((270 + (k - (n - 1) / 2) * spread) * Math.PI) / 180;
    return [Math.cos(t), Math.sin(t)];
  });
}

export function seatPoints(table: Table): Point[] {
  if (table.layout === "arc") return arc(table.seated ? table.seats - 1 : table.seats);
  const a = Math.max(1, (table.width - table.seatWidth) / 2);
  const b = Math.max(1, (table.height - table.seatHeight) / 2);
  const points =
    table.layout === "long"
      ? longTable(table.seats, a, b)
      : ellipse(table.seats, Math.max(1, a / b));
  return table.seated ? points.slice(1) : points;
}
