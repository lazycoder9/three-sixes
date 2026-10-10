defmodule ThreeSixesWeb.TableComponents do
  use Phoenix.Component

  import ThreeSixesWeb.KitchenComponents

  alias ThreeSixes.Game
  alias ThreeSixes.Reaction

  @token_colors [:tomato, :teal, :ochre, :walnut]
  @numbers ~w(no one two three four five six seven eight nine ten eleven twelve)
  @faces ~w(one two three four five six)
  @reaction_labels %{
    "lol" => "Laugh",
    "gasp" => "Gasp",
    "hmm" => "Hmm",
    "clap" => "Clap",
    "fire" => "Fire"
  }

  attr :game, :map, required: true
  attr :step, :integer, required: true
  attr :rolled, :any, default: nil
  attr :tappable, :any, required: true
  attr :reactions, :map, required: true
  attr :waiting?, :boolean, required: true

  def game_table(assigns) do
    ~H"""
    <div id="game-table" class="game-table">
      <div class="game-table__ring">
        <ol class="game-table__seats">
          <.seat
            :for={{seat, x, y} <- ring(@game)}
            seat={seat}
            game={@game}
            x={x}
            y={y}
            tappable={@tappable}
            reaction={@reactions[seat.person.n]}
          />
        </ol>
        <.torn_scrap id="scrap" class="game-table__scrap">
          <.scrap game={@game} />
        </.torn_scrap>
      </div>
      <.my_page
        :if={@game.seated?}
        game={@game}
        step={@step}
        rolled={@rolled}
        reaction={@reactions[hd(@game.seats).person.n]}
      />
      <.torn_scrap :if={!@game.seated?} id="watching" class="game-table__watching">
        {if @game.knocked_out?, do: "You're Knocked out."} You're watching. {head(@game)}
      </.torn_scrap>
      <.reaction_note waiting?={@waiting?} />
    </div>
    """
  end

  defp ring(%{seated?: true, seats: [_me | others]} = game),
    do: place(others, 1, length(game.seats))

  defp ring(game), do: place(game.seats, 0, length(game.seats))

  defp place(seats, first, n) do
    seats
    |> Enum.with_index(first)
    |> Enum.map(fn {seat, i} ->
      angle = :math.pi() / 2 + i * 2 * :math.pi() / n
      {seat, Float.round(:math.cos(angle), 4), Float.round(:math.sin(angle), 4)}
    end)
  end

  attr :seat, :map, required: true
  attr :game, :map, required: true
  attr :x, :float, required: true
  attr :y, :float, required: true
  attr :tappable, :any, required: true
  attr :reaction, :map, default: nil

  defp seat(assigns) do
    assigns = assign(assigns, :turn?, assigns.seat.on_turn? and assigns.game.reveal == nil)

    ~H"""
    <li
      id={"seat-#{@seat.person.n}"}
      class={["seat", @turn? && "is-turn", @seat.penalty? && "is-loser", @seat.out? && "is-out"]}
      aria-current={@turn? && "true"}
      style={"--x: #{@x}; --y: #{@y}"}
    >
      <.person_tap person={@seat.person} tappable={@tappable}>
        <.person_token person={@seat.person} />
        <span class="seat__name">{name(@seat.person)}</span>
      </.person_tap>
      <span :if={@seat.faces} class="seat__dice">
        <.die
          :for={face <- @seat.faces}
          face={face}
          class={["is-flip", counted(face, @game.reveal)]}
        />
        <span :if={@seat.penalty?} class="die is-penalty"></span>
      </span>
      <span :if={!@seat.faces and !@seat.out?} class="seat__dice">
        <span :for={_ <- 1..@seat.dice//1} class="die is-down"></span>
      </span>
      <small :if={@seat.out?} class="seat__out">out</small>
      <span
        :if={@seat.said && !@game.reveal}
        class={["seat__said", said_now?(@seat, @game) && "is-now"]}
      >
        <.bidn count={@seat.said.count} face={@seat.said.face} />
      </span>
      <.reaction :if={@reaction} reaction={@reaction} />
    </li>
    """
  end

  attr :game, :map, required: true

  defp scrap(%{game: %{reveal: %{step: 0} = reveal}} = assigns) do
    assigns = assign(assigns, :reveal, reveal)

    ~H"""
    <p class="scrawl red slam">
      {name(@reveal.checker)} {verb(@reveal.checker, "Checks", "Check")}!
    </p>
    <.bidn count={@reveal.bid.count} face={@reveal.bid.face} />
    """
  end

  defp scrap(%{game: %{reveal: %{} = reveal}} = assigns) do
    assigns = assign(assigns, :reveal, reveal)

    ~H"""
    <p class="scrap__bid faint">Bid <.bidn count={@reveal.bid.count} face={@reveal.bid.face} /></p>
    <p class={["scrap__found", @reveal.count && "slam"]}>
      <.bidn
        count={@reveal.count || "?"}
        face={@reveal.bid.face}
        label={found(@reveal.count, @reveal.bid.face)}
      />
    </p>
    <p :if={@reveal.count} class="scrawl red">
      {if @reveal.stood?, do: "The Bid stands.", else: "Bluff caught."}
    </p>
    <p :if={@reveal.loser} class="scrap__pen">
      {name(@reveal.loser)} <b>+</b><span class="die is-penalty"></span>
      <em :if={@reveal.knocked_out?} class="red">Knocked out</em>
    </p>
    """
  end

  defp scrap(%{game: %{bid: nil}} = assigns) do
    ~H"""
    <p :if={@game.voided_by} class="faint">
      {name(@game.voided_by)} {verb(@game.voided_by, "is", "are")} out. The Round is voided.
    </p>
    <p class="scrawl">{name(@game.turn)} {verb(@game.turn, "opens", "open")} the Round.</p>
    <p class="faint">{@game.dice_on_table} dice on the table</p>
    """
  end

  defp scrap(assigns) do
    ~H"""
    <p class="faint">{name(@game.bid.by)} {verb(@game.bid.by, "bids", "bid")}</p>
    <.bidn count={@game.bid.count} face={@game.bid.face} />
    <p class="faint">{@game.dice_on_table} dice on the table</p>
    """
  end

  defp found(nil, _face), do: "counting"
  defp found(0, face), do: "Not a single #{Enum.at(@faces, face - 1)}."

  defp found(count, face) do
    {first, rest} = count |> words(face) |> String.split_at(1)
    "#{String.upcase(first)}#{rest} on the table."
  end

  defp counted(_face, nil), do: nil
  defp counted(face, %{step: step, bid: %{face: face}}) when step >= 1, do: "is-hit"
  defp counted(_face, %{step: step}) when step >= 1, do: "is-miss"
  defp counted(_face, _reveal), do: nil

  defp tumble_from({round, new_from}, round, i, face) when i >= new_from, do: rem(face, 6) + 1
  defp tumble_from(_rolled, _round, _i, _face), do: nil

  defp said_now?(seat, game), do: game.bid != nil and game.bid.by == seat.person

  attr :game, :map, required: true
  attr :step, :integer, required: true
  attr :rolled, :any, required: true
  attr :reaction, :map, default: nil

  defp my_page(assigns) do
    ~H"""
    <.notebook_page
      id="my-page"
      class={["my-page", @game.my_turn? && "is-turn"]}
      aria-current={@game.my_turn? && "true"}
      phx-hook="PlayKeys"
      data-my-turn={to_string(@game.my_turn?)}
    >
      <div class="hand">
        <span
          :for={{face, i} <- Enum.with_index(@game.my_dice)}
          class={["slot", counted(face, @game.reveal)]}
        >
          <.cube face={face} turns={@game.round} from={tumble_from(@rolled, @game.round, i, face)} />
        </span>
        <span :if={hd(@game.seats).penalty?} class="slot slot--pen">
          <span class="die is-penalty"></span>
        </span>
      </div>
      <p class={["scrawl my-page__head", !@game.my_turn? && "faint"]}>{head(@game)}</p>
      <.offers game={@game} step={@step} />
      <.block
        variant={:tomato}
        size={:big}
        class="my-page__check"
        phx-click="check"
        disabled={!@game.can_check?}
        aria-keyshortcuts="c"
      >
        Check <kbd aria-hidden="true">C</kbd>
      </.block>
      <.reaction :if={@reaction} reaction={@reaction} />
    </.notebook_page>
    """
  end

  attr :game, :map, required: true
  attr :step, :integer, required: true

  defp offers(%{game: %{reveal: %{}}} = assigns) do
    ~H"""
    <div class="opts is-hidden"></div>
    """
  end

  defp offers(assigns) do
    %{bid: bid, dice_on_table: dice_on_table} = assigns.game
    rows = Game.offers(bid, dice_on_table, assigns.step)
    {stepped, at_bid} = Enum.split_with(rows, & &1.stepped?)

    assigns =
      assign(assigns,
        rows: rows,
        at_bid: at_bid,
        stepped: stepped,
        max_step: Game.max_step(bid, dice_on_table),
        opening?: bid == nil,
        off?: !assigns.game.my_turn?
      )

    ~H"""
    <div class={["opts", @off? && "is-off"]}>
      <p :if={@rows == []} class="faint">Nothing higher is left to say.</p>
      <.orow :for={row <- @at_bid} row={row} opening?={@opening?} off?={@off?} />
      <div :if={@stepped != []} class="ostep">
        <span class="ostep__buttons">
          <button
            type="button"
            class="round-button"
            phx-click="step"
            phx-value-by="-1"
            aria-label="One fewer"
            disabled={@off? or @step <= 0}
          >
            &minus;
          </button>
          <button
            type="button"
            class="round-button"
            phx-click="step"
            phx-value-by="1"
            aria-label="One more"
            disabled={@off? or @step >= @max_step}
          >
            +
          </button>
        </span>
        <div class="ostep__rows">
          <.orow :for={row <- @stepped} row={row} opening?={@opening?} off?={@off?} />
        </div>
      </div>
    </div>
    <p :if={@rows != []} class={["keyhint", @off? && "is-off"]}>
      <span><kbd>1</kbd>–<kbd>6</kbd> {if @opening?, do: "Bid", else: "Raise"}</span>
      <span :if={@max_step > 0}>
        <span class="keyhint__dot">·</span> <kbd>←</kbd> <kbd>→</kbd> fewer or more dice
      </span>
    </p>
    """
  end

  attr :row, :map, required: true
  attr :opening?, :boolean, required: true
  attr :off?, :boolean, required: true

  defp orow(assigns) do
    ~H"""
    <div class="orow">
      <b>{@row.count} &times;</b>
      <%= for face <- 1..6 do %>
        <button
          :if={face in @row.faces}
          type="button"
          class="pickdie"
          phx-click="raise"
          phx-value-count={@row.count}
          phx-value-face={face}
          aria-label={"#{if @opening?, do: "Bid", else: "Raise to"} #{words(@row.count, face)}"}
          disabled={@off?}
        >
          <.die face={face} />
        </button>
        <span :if={face not in @row.faces} class="pickgap"></span>
      <% end %>
    </div>
    """
  end

  attr :count, :any, required: true
  attr :face, :integer, required: true
  attr :label, :string, default: nil

  defp bidn(assigns) do
    ~H"""
    <span class="bidn" role="img" aria-label={@label || words(@count, @face)}>
      <b>{@count}</b><i>&times;</i> <.die face={@face} />
    </span>
    """
  end

  defp words(count, face) do
    face_word = Enum.at(@faces, face - 1)
    number = Enum.at(@numbers, count, Integer.to_string(count))

    cond do
      count == 1 -> "#{number} #{face_word}"
      face == 6 -> "#{number} sixes"
      true -> "#{number} #{face_word}s"
    end
  end

  defp head(%{my_turn?: true, bid: nil}), do: "You open. Make a Bid."
  defp head(%{my_turn?: true}), do: "Your turn. Raise it, or Check it."
  defp head(%{turn: nil}), do: ""
  defp head(%{turn: turn}), do: "Waiting for #{turn.nickname}."

  attr :spectators, :list, required: true
  attr :open?, :boolean, required: true
  attr :tappable, :any, required: true
  attr :reactions, :map, required: true

  def spectators(assigns) do
    assigns =
      assign(assigns, :reactions, unseated_reactions(assigns.spectators, assigns.reactions))

    ~H"""
    <div class="spec">
      <button
        id="spectators-chip"
        type="button"
        class="spec__chip"
        phx-click="spectators"
        aria-expanded={to_string(@open?)}
        aria-controls="spectators"
      >
        {spectator_count(length(@spectators))}<i aria-hidden="true"></i>
      </button>
      <.reaction :for={{_n, reaction} <- @reactions} :if={!@open?} reaction={reaction} side? />
      <ul id="spectators" class="spec__list" hidden={!@open?}>
        <li :for={spectator <- @spectators} id={"spectator-#{spectator.person.n}"}>
          <.person_tap person={spectator.person} tappable={@tappable}>
            <.person_token person={spectator.person} />
            <span>{name(spectator.person)}</span>
          </.person_tap>
          <small :if={spectator.out?}>out</small>
          <.reaction
            :if={@open? && @reactions[spectator.person.n]}
            reaction={@reactions[spectator.person.n]}
            side?
          />
        </li>
      </ul>
    </div>
    """
  end

  defp unseated_reactions(spectators, reactions) do
    unseated = for %{person: %{n: n}, out?: false} <- spectators, do: n
    Map.take(reactions, unseated)
  end

  defp spectator_count(1), do: "1 Spectator"
  defp spectator_count(count), do: "#{count} Spectators"

  attr :waiting?, :boolean, required: true

  def reaction_note(assigns) do
    assigns = assign(assigns, :keys, Reaction.all())

    ~H"""
    <div
      id="reactions"
      class={["reactions", @waiting? && "is-cooling"]}
      role="group"
      aria-label="Send a Reaction"
    >
      <button
        :for={key <- @keys}
        type="button"
        class="reactions__button"
        phx-click="react"
        phx-value-reaction={key}
        aria-label={reaction_label(key)}
        aria-disabled={@waiting? && "true"}
      >
        {Reaction.text(key)}
      </button>
    </div>
    """
  end

  attr :reaction, :map, required: true
  attr :side?, :boolean, default: false

  def reaction(assigns) do
    ~H"""
    <span
      id={"reaction-#{@reaction.by.n}-#{@reaction.id}"}
      class={["reaction", @side? && "reaction--side"]}
      role="img"
      aria-label={"#{name(@reaction.by)}: #{reaction_label(@reaction.key)}"}
    >
      {Reaction.text(@reaction.key)}
    </span>
    """
  end

  defp reaction_label(key), do: Map.get(@reaction_labels, key, Reaction.text(key))

  attr :person, :map, required: true
  attr :tappable, :any, required: true
  slot :inner_block, required: true

  def person_tap(assigns) do
    ~H"""
    <button
      :if={@person.n in @tappable}
      type="button"
      class="person-button"
      popovertarget={"person-dialog-#{@person.n}"}
    >
      {render_slot(@inner_block)}
    </button>
    <%= if @person.n not in @tappable do %>
      {render_slot(@inner_block)}
    <% end %>
    """
  end

  attr :person, :map, required: true

  def person_token(assigns) do
    ~H"""
    <.token initial={initial(@person.nickname)} color={token_color(@person.n)} />
    """
  end

  defp name(%{me?: true}), do: "You"
  defp name(person), do: person.nickname

  defp verb(%{me?: true}, _one, you), do: you
  defp verb(_person, one, _you), do: one

  defp initial(nickname), do: nickname |> String.first() |> String.upcase()

  defp token_color(n), do: Enum.at(@token_colors, rem(n - 1, length(@token_colors)))
end
