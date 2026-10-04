import { describe, expect, test } from "bun:test";
import { ThemeSwitch } from "./theme_switch";

function mountSwitch(theme: string) {
  const root = { dataset: { theme } as Record<string, string> };
  Object.assign(globalThis, {
    document: { documentElement: root },
    localStorage: { setItem: () => {} },
  });
  const attributes: Record<string, string> = {};
  let onClick: (() => void) | undefined;
  const el = {
    setAttribute: (name: string, value: string) => (attributes[name] = value),
    addEventListener: (_type: string, listener: () => void) => (onClick = listener),
  };
  const hook = { el } as unknown as ThisParameterType<NonNullable<typeof ThemeSwitch.mounted>>;
  ThemeSwitch.mounted?.call(hook);
  return {
    root,
    attributes,
    click: () => onClick?.(),
    update: () => ThemeSwitch.updated?.call(hook),
  };
}

describe("the theme switch", () => {
  test("reads as pressed while the dark theme is on", () => {
    expect(mountSwitch("dark").attributes["aria-pressed"]).toBe("true");
    expect(mountSwitch("light").attributes["aria-pressed"]).toBe("false");
  });

  test("a press flips the theme and the pressed state together", () => {
    const toggle = mountSwitch("light");
    toggle.click();
    expect(toggle.root.dataset.theme).toBe("dark");
    expect(toggle.attributes["aria-pressed"]).toBe("true");
  });

  test("keeps the pressed state when the page is patched", () => {
    const toggle = mountSwitch("dark");
    delete toggle.attributes["aria-pressed"];
    toggle.update();
    expect(toggle.attributes["aria-pressed"]).toBe("true");
  });
});
