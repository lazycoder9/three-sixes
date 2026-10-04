import { describe, expect, test } from "bun:test";

const source = await Bun.file(new URL("theme_boot.js", import.meta.url)).text();

function themeBeforePaint(stored: string | null, systemDark: boolean): string | undefined {
  const root = { dataset: {} as Record<string, string> };
  const storage = { getItem: (key: string) => (key === "theme" ? stored : null) };
  const matchMedia = (query: string) => ({
    matches: query === "(prefers-color-scheme: dark)" && systemDark,
  });
  new Function("document", "localStorage", "matchMedia", source)(
    { documentElement: root },
    storage,
    matchMedia,
  );
  return root.dataset.theme;
}

describe("the theme applied before first paint", () => {
  test("a stored choice wins over the system setting", () => {
    expect(themeBeforePaint("dark", false)).toBe("dark");
    expect(themeBeforePaint("light", true)).toBe("light");
  });

  test("with no stored choice it follows the system setting", () => {
    expect(themeBeforePaint(null, true)).toBe("dark");
    expect(themeBeforePaint(null, false)).toBe("light");
  });

  test("a stored value that is not a theme is ignored", () => {
    expect(themeBeforePaint("sepia", true)).toBe("dark");
  });
});
