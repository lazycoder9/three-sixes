import type { Hook } from "phoenix_live_view";

export const ThemeSwitch: Hook = {
  mounted() {
    this.el.addEventListener("click", () => {
      const root = document.documentElement;
      const theme = root.dataset.theme === "dark" ? "light" : "dark";
      root.dataset.theme = theme;
      try {
        localStorage.setItem("theme", theme);
      } catch {
        // Blocked storage only means the choice lasts until the page is closed.
      }
    });
  },
};
