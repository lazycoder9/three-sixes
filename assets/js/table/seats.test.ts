import { describe, expect, test } from "bun:test";
import { seatPoints, type Point } from "./seats";

const seatBox = { seatWidth: 100, seatHeight: 100 };

function expectPoints(actual: Point[], expected: Point[]) {
  expect(actual).toHaveLength(expected.length);
  actual.forEach(([x, y], i) => {
    expect(x).toBeCloseTo(expected[i][0], 2);
    expect(y).toBeCloseTo(expected[i][1], 2);
  });
}

function edgeLength(ratio: number, from: number, to: number) {
  const steps = 2000;
  let length = 0;
  for (let i = 0; i < steps; i++) {
    const t = from + ((i + 0.5) / steps) * (to - from);
    length += Math.hypot(ratio * Math.sin(t), Math.cos(t)) * ((to - from) / steps);
  }
  return length;
}

function gapsAlongEdge(points: Point[], ratio: number) {
  const angles = points.map(([x, y]) => Math.atan2(y, x));
  return angles.map((from, i) => {
    let to = angles[(i + 1) % angles.length];
    while (to <= from) to += 2 * Math.PI;
    return edgeLength(ratio, from, to);
  });
}

function evenlySpaced(gaps: number[]) {
  return Math.max(...gaps) / Math.min(...gaps) < 1.01;
}

describe("seats around a ring", () => {
  test("start at the bottom and go clockwise on screen", () => {
    const points = seatPoints({
      seats: 4,
      seated: false,
      layout: "ring",
      width: 300,
      height: 300,
      ...seatBox,
    });
    expectPoints(points, [
      [0, 1],
      [-1, 0],
      [0, -1],
      [1, 0],
    ]);
  });

  test("are spaced evenly along the edge of a wide table, where equal angles would not be", () => {
    const wide = {
      seats: 8,
      seated: false,
      layout: "ring",
      width: 700,
      height: 300,
      ...seatBox,
    } as const;
    expect(evenlySpaced(gapsAlongEdge(seatPoints(wide), 3))).toBe(true);

    const equalAngles = Array.from({ length: 8 }, (_, k): Point => {
      const t = Math.PI / 2 + (k / 8) * 2 * Math.PI;
      return [Math.cos(t), Math.sin(t)];
    });
    expect(evenlySpaced(gapsAlongEdge(equalAngles, 3))).toBe(false);
  });

  test("are spaced evenly along the edge of a tall table, as on a phone", () => {
    const tall = {
      seats: 5,
      seated: false,
      layout: "ring",
      width: 300,
      height: 700,
      ...seatBox,
    } as const;
    expect(evenlySpaced(gapsAlongEdge(seatPoints(tall), 1 / 3))).toBe(true);
  });

  test("leave the bottom spot free for you when you are seated", () => {
    const table = { seats: 6, layout: "ring", width: 700, height: 300, ...seatBox } as const;
    const watching = seatPoints({ ...table, seated: false });
    expect(watching).toHaveLength(6);
    expectPoints(seatPoints({ ...table, seated: true }), watching.slice(1));
  });
});

describe("seats around a long table", () => {
  const halfWidth = 300;
  const halfHeight = 100;
  const straight = halfWidth - halfHeight;
  const long = {
    seats: 12,
    seated: false,
    layout: "long",
    width: 700,
    height: 300,
    ...seatBox,
  } as const;

  test("sit on two straight sides and two round ends, starting at the bottom", () => {
    const points = seatPoints(long);
    expect(points).toHaveLength(12);
    expectPoints(points.slice(0, 1), [[0, 1]]);

    const onSides = points.filter(([x]) => Math.abs(x) * halfWidth <= straight + 1e-9);
    const onEnds = points.filter((point) => !onSides.includes(point));
    expect(onSides.length).toBeGreaterThan(0);
    expect(onEnds.length).toBeGreaterThan(0);
    for (const [, y] of onSides) expect(Math.abs(y)).toBeCloseTo(1, 9);
    for (const [x, y] of onEnds) {
      expect(Math.hypot(Math.abs(x) * halfWidth - straight, y * halfHeight)).toBeCloseTo(
        halfHeight,
        6,
      );
    }
  });

  test("go clockwise on screen: along the bottom to the left end first", () => {
    const [, second] = seatPoints(long);
    expect(second[0]).toBeLessThan(0);
    expect(second[1]).toBe(1);
  });

  test("stay an ellipse when the table is not wide enough for straight sides", () => {
    const points = seatPoints({ ...long, width: 360, height: 300 });
    expect(points).toHaveLength(12);
    for (const [x, y] of points) expect(Math.hypot(x, y)).toBeCloseTo(1, 9);

    const justLong = seatPoints({ ...long, width: 380, height: 300 });
    expect(justLong.some(([x, y]) => Math.abs(Math.hypot(x, y) - 1) > 0.01)).toBe(true);
  });
});

const degrees = ([x, y]: Point) => ((Math.atan2(y, x) * 180) / Math.PI + 360) % 360;

describe("seats on an arc across the top", () => {
  const arc = { seated: true, layout: "arc", width: 390, height: 400, ...seatBox } as const;

  test("spread four others left to right over the top, centred on it", () => {
    expectPoints(seatPoints({ ...arc, seats: 5 }), [
      [-0.9659, -0.2588],
      [-0.4226, -0.9063],
      [0.4226, -0.9063],
      [0.9659, -0.2588],
    ]);
  });

  test("put one other straight across the top", () => {
    expectPoints(seatPoints({ ...arc, seats: 2 }), [[0, -1]]);
  });

  test("stay in the top half and span at most 150 degrees", () => {
    for (const seats of [2, 3, 4, 5]) {
      const points = seatPoints({ ...arc, seats });
      expect(points).toHaveLength(seats - 1);
      for (const [, y] of points) expect(y).toBeLessThan(0);
      const angles = points.map(degrees);
      expect(Math.max(...angles) - Math.min(...angles)).toBeLessThanOrEqual(150 + 1e-9);
    }
  });
});
