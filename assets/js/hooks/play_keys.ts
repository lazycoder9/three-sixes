import type { Hook } from "phoenix_live_view";

const PRESS_KEYS = new Set(["1", "2", "3", "4", "5", "6", "c", "C"]);
const STEP_KEYS = new Set(["ArrowLeft", "ArrowRight", "+", "-"]);

const FIELD_TAGS = new Set(["INPUT", "TEXTAREA", "SELECT"]);

function isField(target: HTMLElement | null): boolean {
  return target !== null && (FIELD_TAGS.has(target.tagName) || target.isContentEditable);
}

function matches(doc: Pick<Document, "querySelector">, selector: string): boolean {
  try {
    return doc.querySelector(selector) !== null;
  } catch {
    // A browser without the Popover API throws on :popover-open, and has no popover to be open.
    return false;
  }
}

function dialogOpen(doc: Pick<Document, "querySelector">): boolean {
  return matches(doc, ":popover-open") || matches(doc, "dialog[open]");
}

export function playKey(
  event: KeyboardEvent,
  doc: Pick<Document, "querySelector">,
  myTurn: boolean,
): string | null {
  if (!myTurn) return null;
  if (event.ctrlKey || event.metaKey || event.altKey || event.isComposing) return null;
  if (isField(event.target as HTMLElement | null)) return null;
  if (dialogOpen(doc)) return null;
  if (STEP_KEYS.has(event.key)) return event.key;
  if (PRESS_KEYS.has(event.key) && !event.repeat) return event.key;
  return null;
}

type PlayKeysHook = Hook<{ onKey: (event: KeyboardEvent) => void }>;

export const PlayKeys: PlayKeysHook = {
  mounted() {
    this.onKey = (event) => {
      const key = playKey(event, document, this.el.dataset.myTurn === "true");
      if (key === null) return;
      event.preventDefault();
      this.pushEvent("key", { key });
    };
    window.addEventListener("keydown", this.onKey);
  },
  destroyed() {
    window.removeEventListener("keydown", this.onKey);
  },
};
