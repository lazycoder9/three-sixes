import type { Hook } from "phoenix_live_view";

function showPressed(el: HTMLElement) {
  el.setAttribute("aria-pressed", String(document.documentElement.dataset.theme === "dark"));
}

export const ThemeSwitch: Hook = {
  mounted() {
    showPressed(this.el);
    this.el.addEventListener("click", () => {
      const root = document.documentElement;
      const theme = root.dataset.theme === "dark" ? "light" : "dark";
      root.dataset.theme = theme;
      showPressed(this.el);
      try {
        localStorage.setItem("theme", theme);
      } catch {
        // Blocked storage only means the choice lasts until the page is closed.
      }
    });
  },
  updated() {
    showPressed(this.el);
  },
};
