import { describe, expect, test } from "bun:test";
import { PlayKeys } from "./play_keys";

type Listener = (event: KeyboardEvent) => void;

function mountKeys({
  myTurn = true,
  querySelector = (_selector: string): object | null => null,
} = {}) {
  const listeners = new Set<Listener>();
  Object.assign(globalThis, {
    window: {
      addEventListener: (_type: string, listener: Listener) => listeners.add(listener),
      removeEventListener: (_type: string, listener: Listener) => listeners.delete(listener),
    },
    document: { querySelector },
  });
  const pushed: unknown[] = [];
  const el = { dataset: { myTurn: String(myTurn) } as Record<string, string> };
  const hook = {
    el,
    pushEvent: (event: string, payload: unknown) => pushed.push([event, payload]),
  } as unknown as ThisParameterType<NonNullable<typeof PlayKeys.mounted>>;
  PlayKeys.mounted?.call(hook);

  function press(key: string, init: Record<string, unknown> = {}) {
    let prevented = false;
    const event = {
      key,
      ctrlKey: false,
      metaKey: false,
      altKey: false,
      shiftKey: false,
      repeat: false,
      isComposing: false,
      target: { tagName: "BODY", isContentEditable: false },
      preventDefault: () => (prevented = true),
      ...init,
    } as unknown as KeyboardEvent;
    for (const listener of listeners) listener(event);
    return prevented;
  }

  return {
    el,
    pushed,
    listeners,
    press,
    destroy: () => PlayKeys.destroyed?.call(hook),
  };
}

describe("play keys", () => {
  test.each(["1", "2", "3", "4", "5", "6", "ArrowLeft", "ArrowRight", "+", "-", "c", "C"])(
    "%s on my turn is pushed and the browser's default is stopped",
    (key) => {
      const keys = mountKeys();
      expect(keys.press(key)).toBe(true);
      expect(keys.pushed).toEqual([["key", { key }]]);
    },
  );

  test.each(["7", "0", "=", "a", "Enter", " ", "ArrowUp", "Escape"])("%s is left alone", (key) => {
    const keys = mountKeys();
    expect(keys.press(key)).toBe(false);
    expect(keys.pushed).toEqual([]);
  });

  test("off my turn nothing is pushed and the key keeps its default", () => {
    const keys = mountKeys({ myTurn: false });
    expect(keys.press("3")).toBe(false);
    expect(keys.pushed).toEqual([]);
  });

  test("my turn is read at the key press, as patches change it", () => {
    const keys = mountKeys({ myTurn: false });
    keys.el.dataset.myTurn = "true";
    keys.press("c");
    keys.el.dataset.myTurn = "false";
    keys.press("c");
    expect(keys.pushed).toEqual([["key", { key: "c" }]]);
  });

  test.each(["ctrlKey", "metaKey", "altKey"])(
    "with %s held a key is a shortcut, not play",
    (modifier) => {
      const keys = mountKeys();
      expect(keys.press("c", { [modifier]: true })).toBe(false);
      expect(keys.press("4", { [modifier]: true })).toBe(false);
      expect(keys.pushed).toEqual([]);
    },
  );

  test("Shift is allowed, since + needs it", () => {
    const keys = mountKeys();
    keys.press("+", { shiftKey: true });
    keys.press("C", { shiftKey: true });
    expect(keys.pushed).toEqual([
      ["key", { key: "+" }],
      ["key", { key: "C" }],
    ]);
  });

  test.each(["INPUT", "TEXTAREA", "SELECT"])("typing in a %s is left to the field", (tagName) => {
    const keys = mountKeys();
    expect(keys.press("2", { target: { tagName, isContentEditable: false } })).toBe(false);
    expect(keys.pushed).toEqual([]);
  });

  test("typing in a contenteditable is left to it", () => {
    const keys = mountKeys();
    keys.press("c", { target: { tagName: "DIV", isContentEditable: true } });
    expect(keys.pushed).toEqual([]);
  });

  test("a focused button still plays", () => {
    const keys = mountKeys();
    keys.press("5", { target: { tagName: "BUTTON", isContentEditable: false } });
    expect(keys.pushed).toEqual([["key", { key: "5" }]]);
  });

  test.each([":popover-open", "dialog[open]"])(
    "with %s on the page keys are left alone",
    (open) => {
      const keys = mountKeys({ querySelector: (selector) => (selector === open ? {} : null) });
      expect(keys.press("c")).toBe(false);
      expect(keys.pushed).toEqual([]);
    },
  );

  test("a browser that cannot match :popover-open counts no popover as open", () => {
    const keys = mountKeys({
      querySelector: (selector) => {
        if (selector.includes(":popover-open")) throw new SyntaxError(selector);
        return null;
      },
    });
    keys.press("1");
    expect(keys.pushed).toEqual([["key", { key: "1" }]]);
  });

  test("a browser that cannot match :popover-open still sees an open dialog", () => {
    const keys = mountKeys({
      querySelector: (selector) => {
        if (selector.includes(":popover-open")) throw new SyntaxError(selector);
        return selector === "dialog[open]" ? {} : null;
      },
    });
    keys.press("1");
    expect(keys.pushed).toEqual([]);
  });

  test.each(["4", "c", "C"])("holding %s down sends one press", (key) => {
    const keys = mountKeys();
    keys.press(key);
    expect(keys.press(key, { repeat: true })).toBe(false);
    expect(keys.pushed).toEqual([["key", { key }]]);
  });

  test.each(["ArrowLeft", "ArrowRight", "+", "-"])("holding %s down keeps stepping", (key) => {
    const keys = mountKeys();
    keys.press(key);
    keys.press(key, { repeat: true });
    expect(keys.pushed).toEqual([
      ["key", { key }],
      ["key", { key }],
    ]);
  });

  test("a key pressed while an input method is composing is left to it", () => {
    const keys = mountKeys();
    expect(keys.press("3", { isComposing: true })).toBe(false);
    expect(keys.pushed).toEqual([]);
  });

  test("once the page is gone keys are no longer heard", () => {
    const keys = mountKeys();
    keys.destroy();
    keys.press("c");
    expect(keys.listeners.size).toBe(0);
    expect(keys.pushed).toEqual([]);
  });
});
