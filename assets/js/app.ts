import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket, type LiveSocketInstanceInterface } from "phoenix_live_view";
import { hooks as colocatedHooks } from "phoenix-colocated/three_sixes";
import topbar from "../vendor/topbar";
import { ThemeSwitch } from "./hooks/theme_switch";

interface LiveReloader {
  enableServerLogs(): void;
  openEditorAtCaller(target: EventTarget | null): void;
  openEditorAtDef(target: EventTarget | null): void;
}

declare global {
  interface Window {
    liveSocket: LiveSocketInstanceInterface;
    liveReloader: LiveReloader;
  }
}

const NICKNAME_KEY = "three-sixes:nickname";

const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content");
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: () => ({ _csrf_token: csrfToken, nickname: localStorage.getItem(NICKNAME_KEY) }),
  hooks: { ...colocatedHooks, ThemeSwitch },
});

const mustard = getComputedStyle(document.documentElement).getPropertyValue("--color-mustard");
topbar.config({ barColors: { 0: mustard }, shadowColor: "rgba(0, 0, 0, .3)" });
const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
window.addEventListener("phx:page-loading-start", (_info) => {
  if (!reducedMotion.matches) topbar.show(300);
});
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

window.addEventListener("phx:remember-nickname", ((event: CustomEvent<{ nickname: string }>) => {
  localStorage.setItem(NICKNAME_KEY, event.detail.nickname);
}) as EventListener);

window.addEventListener("three-sixes:copy", ((event: CustomEvent<{ text: string }>) => {
  const status = (event.target as Element).closest(".copy-link")?.querySelector("[role=status]");
  if (!status) return;
  const copied = "Room link copied";
  Promise.resolve()
    .then(() => navigator.clipboard.writeText(event.detail.text))
    .then(
      () => {
        status.textContent = copied;
        setTimeout(() => {
          if (status.textContent === copied) status.textContent = "";
        }, 3000);
      },
      () => (status.textContent = event.detail.text),
    );
}) as EventListener);

liveSocket.connect();

window.liveSocket = liveSocket;

if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ((event: CustomEvent<LiveReloader>) => {
    const reloader = event.detail;
    reloader.enableServerLogs();

    let keyDown: string | null = null;
    window.addEventListener("keydown", (e) => (keyDown = e.key));
    window.addEventListener("keyup", () => (keyDown = null));
    window.addEventListener(
      "click",
      (e) => {
        if (keyDown === "c") {
          e.preventDefault();
          e.stopImmediatePropagation();
          reloader.openEditorAtCaller(e.target);
        } else if (keyDown === "d") {
          e.preventDefault();
          e.stopImmediatePropagation();
          reloader.openEditorAtDef(e.target);
        }
      },
      true,
    );

    window.liveReloader = reloader;
  }) as EventListener);
}
