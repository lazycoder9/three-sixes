defmodule ThreeSixesWeb.LandingLive do
  use ThreeSixesWeb, :live_view

  alias ThreeSixes.Dice
  alias ThreeSixesWeb.RollCaption

  @tumbles_in_from [2, 5, 3]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       faces: [6, 6, 6],
       rolls: 0,
       caption: "Three sixes. The Bid this game is named after."
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

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :tumbles_in_from, @tumbles_in_from)

    ~H"""
    <Layouts.app flash={@flash}>
      <section class="screen">
        <div class="hero">
          <div>
            <h1 class="headline"><span>Roll in secret.</span> <span>Lie out loud.</span></h1>
            <p class="lede">
              Three Sixes is a dice-bluffing game for a Room of friends. Everyone hides their dice, then Bids on what's under every cup at once.
            </p>
            <div class="door">
              <.block variant={:tomato} size={:big}>Create a Room</.block>
              <fieldset>
                <legend class="legend">Join with a code</legend>
                <div class="tiles">
                  <.letter_tile_input aria-label="Room code, letter 1" maxlength="1" />
                  <.letter_tile_input aria-label="Letter 2" maxlength="1" />
                  <.letter_tile_input aria-label="Letter 3" maxlength="1" />
                  <.letter_tile_input aria-label="Letter 4" maxlength="1" />
                  <.block>Join</.block>
                </div>
              </fieldset>
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
              Cups up. Whoever was wrong takes a Penalty die. Take your sixth and you're Knocked out.
            </.torn_scrap>
          </li>
        </ol>
      </section>
    </Layouts.app>
    """
  end
end
