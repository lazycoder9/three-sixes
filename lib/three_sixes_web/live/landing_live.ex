defmodule ThreeSixesWeb.LandingLive do
  use ThreeSixesWeb, :live_view

  alias ThreeSixes.Dice
  alias ThreeSixes.RoomCode
  alias ThreeSixes.Rooms
  alias ThreeSixesWeb.RollCaption

  @tumbles_in_from [2, 5, 3]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       faces: [6, 6, 6],
       rolls: 0,
       caption: "Three sixes. The Bid this game is named after.",
       code_error: nil
     )}
  end

  @impl true
  def handle_event("roll", _params, socket) do
    faces = Dice.roll(3)

    {:noreply,
     assign(socket,
       faces: faces,
       rolls: socket.assigns.rolls + 1,
       caption: RollCaption.for_faces(faces)
     )}
  end

  def handle_event("create", _params, socket) do
    case Rooms.create(socket.assigns.person_id, socket.assigns.client_address) do
      {:ok, code} ->
        {:noreply, push_navigate(socket, to: ~p"/r/#{code}")}

      {:error, :busy} ->
        {:noreply,
         put_flash(socket, :error, "Every Room is busy right now. Try again in a few minutes.")}

      {:error, :too_many} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "You can't open more Rooms right now. Try again in a few minutes."
         )}
    end
  end

  def handle_event("join", %{"code" => letters}, socket) when is_list(letters) do
    code = letters |> Enum.join() |> RoomCode.normalize()

    if String.length(code) == 4 do
      {:noreply, push_navigate(socket, to: ~p"/r/#{code}")}
    else
      {:noreply, assign(socket, code_error: "A Room code is four letters.")}
    end
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :tumbles_in_from, @tumbles_in_from)

    ~H"""
    <Layouts.app flash={@flash} account={@account} return_to={~p"/"}>
      <section class="screen">
        <div class="hero">
          <div>
            <h1 class="headline"><span>Roll in secret.</span> <span>Lie out loud.</span></h1>
            <p class="lede">
              Three Sixes is a dice-bluffing game for a Room of friends. Everyone hides their dice, then Bids on what's under every cup at once.
            </p>
            <div class="door">
              <.block variant={:tomato} size={:big} phx-click="create">Create a Room</.block>
              <form id="join-code" class={@code_error && "is-error"} phx-submit="join">
                <fieldset>
                  <legend class="legend">Join with a code</legend>
                  <p :if={@code_error} class="code-error" role="alert">{@code_error}</p>
                  <div id="code-tiles" class="tiles" phx-hook=".CodeTiles">
                    <.letter_tile_input name="code[]" aria-label="Room code, letter 1" />
                    <.letter_tile_input name="code[]" aria-label="Letter 2" />
                    <.letter_tile_input name="code[]" aria-label="Letter 3" />
                    <.letter_tile_input name="code[]" aria-label="Letter 4" />
                    <.block type="submit">Join</.block>
                  </div>
                </fieldset>
              </form>
              <script :type={Phoenix.LiveView.ColocatedHook} name=".CodeTiles">
                export default {
                  mounted() {
                    const tiles = () => [...this.el.querySelectorAll("input")];

                    const place = (tile) => {
                      const cells = tiles();
                      const i = cells.indexOf(tile);
                      const letters = tile.value.replace(/[^a-z]/gi, "");

                      if (letters.length > 1) {
                        [...letters].slice(0, 4 - i).forEach((letter, k) => (cells[i + k].value = letter));
                        cells[Math.min(i + letters.length, 3)].focus();
                      } else {
                        if (tile.value !== letters) tile.value = letters;
                        if (letters && cells[i + 1]) cells[i + 1].focus();
                      }
                    };

                    this.el.addEventListener("input", (event) => {
                      if (!event.isComposing) place(event.target);
                    });
                    this.el.addEventListener("compositionend", (event) => place(event.target));

                    this.el.addEventListener("keydown", (event) => {
                      if (event.key !== "Backspace" || event.target.value) return;
                      const cells = tiles();
                      const previous = cells[cells.indexOf(event.target) - 1];
                      if (!previous) return;
                      event.preventDefault();
                      previous.value = "";
                      previous.focus();
                    });

                    this.el.addEventListener("focusin", (event) => event.target.select?.());
                  },
                };
              </script>
            </div>
          </div>

          <div class="hero__paper">
            <.notebook_page>
              <span class="mug-ring" aria-hidden="true"></span>
              <button
                id="dice"
                type="button"
                class="pile"
                phx-click="roll"
                aria-label="Roll the dice"
                aria-describedby="dice-caption"
              >
                <span :for={{face, from} <- Enum.zip(@faces, @tumbles_in_from)} class="slot">
                  <.cube
                    face={face}
                    turns={@rolls + 1}
                    from={if @rolls == 0, do: from}
                    class={if rem(@rolls, 2) == 1, do: "is-rolling", else: "is-rolling-again"}
                  />
                </span>
              </button>
              <p id="dice-caption" class="caption" aria-live="polite">
                <span id={"caption-#{@rolls}"} class={@rolls > 0 && "is-new"}>{@caption}</span>
              </p>
              <p class="faint">tap the dice to roll</p>
            </.notebook_page>
            <span class="pencil" aria-hidden="true"></span>
            <span class="pencil-tip" aria-hidden="true"></span>
          </div>
        </div>

        <ol class="rules">
          <li>
            <.torn_scrap>
              <b>Roll in secret</b> Everyone starts with one die under their own cup.
            </.torn_scrap>
          </li>
          <li>
            <.torn_scrap>
              <b>Bid, or Raise</b>
              Say how many of one face are on the whole table. The next Player Raises it or Checks it.
            </.torn_scrap>
          </li>
          <li>
            <.torn_scrap>
              <b>Check</b>
              Cups up. Whoever was wrong takes a Penalty die, two on three sixes. Reach six dice and you're Knocked out.
            </.torn_scrap>
          </li>
        </ol>
      </section>
    </Layouts.app>
    """
  end
end
