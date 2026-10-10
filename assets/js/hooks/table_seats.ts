import type { Hook } from "phoenix_live_view";
import { seatPoints, type Layout } from "../table/seats";

const phone = matchMedia("(width < 720px)");

function layout(table: HTMLElement): Layout {
  const marked = (marker: string) => table.classList.contains(`game-table--${marker}`);
  if (phone.matches && marked("arc")) return "arc";
  if (marked("long") || (phone.matches && marked("phone-compact"))) return "long";
  return "ring";
}

function place(table: HTMLElement) {
  const box = table.querySelector<HTMLElement>(".game-table__seats");
  const seats = [...(box?.querySelectorAll<HTMLElement>(".seat") ?? [])];
  if (!box || seats.length === 0) return;
  const seat = getComputedStyle(seats[0]);
  const points = seatPoints({
    seats: Number(table.dataset.seats),
    seated: table.hasAttribute("data-seated"),
    layout: layout(table),
    width: box.clientWidth,
    height: box.clientHeight,
    seatWidth: parseFloat(seat.getPropertyValue("--sw")),
    seatHeight: parseFloat(seat.getPropertyValue("--sh")),
  });
  seats.forEach((el, i) => {
    const point = points[i];
    if (!point) return;
    el.style.setProperty("--x", point[0].toFixed(4));
    el.style.setProperty("--y", point[1].toFixed(4));
  });
}

type State = { observer: ResizeObserver; place: () => void };

export const TableSeats: Hook<State> = {
  mounted() {
    this.place = () => place(this.el);
    this.observer = new ResizeObserver(this.place);
    this.observer.observe(this.el.querySelector(".game-table__seats") ?? this.el);
    phone.addEventListener("change", this.place);
    this.place();
  },
  // A patch drops the inline positions, since the server never renders them.
  updated() {
    this.place();
  },
  destroyed() {
    this.observer.disconnect();
    phone.removeEventListener("change", this.place);
  },
};
