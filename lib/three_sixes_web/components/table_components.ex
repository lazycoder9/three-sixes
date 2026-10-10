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
  attr :rolled, :integer, default: nil
  attr :tappable, :any, required: true
  attr :reactions, :map, required: true
  attr :waiting?, :boolean, required: true
  attr :away, :map, required: true
  attr :now, :integer, required: true

  def game_table(assigns) do
    seats = length(assigns.game.seats)
    shown = if assigns.game.seated?, do: tl(assigns.game.seats), else: assigns.game.seats
    assigns = assign(assigns, seats: seats, shown: shown, compact?: seats > 8)

    ~H"""
    <div
      id="game-table"
      class={[
        "game-table",
        @compact? && "game-table--long",
        @seats > 5 && "game-table--phone-compact",
        @game.seated? && @seats <= 5 && "game-table--arc"
      ]}
      phx-hook="TableSeats"
      data-seats={@seats}
      data-seated={@game.seated?}
    >
      <div class="game-table__ring">
        <ol class="game-table__seats">
          <.seat
            :for={seat <- @shown}
            seat={seat}
            game={@game}
            compact?={@compact?}
            tappable={@tappable}
            reaction={@reactions[seat.person.n]}
            since={@away[seat.person.n]}
            now={@now}
          />
        </ol>
        <.torn_scrap id="scrap" class="game-table__scrap">
          <.scrap game={@game} />
          <span
            :if={@game.three_sixes?}
            id={"three-sixes-#{@game.round}"}
            class="three-sixes"
            aria-hidden="true"
          >
            3 <small>&times;</small> <.die face={6} />
          </span>
        </.torn_scrap>
      </div>
      <.my_dice :if={@game.seated?} game={@game} rolled={@rolled} />
      <div class="game-table__bottom">
        <.my_page
          :if={@game.seated?}
          game={@game}
          step={@step}
          reaction={@reactions[hd(@game.seats).person.n]}
        />
        <.torn_scrap :if={!@game.seated?} id="watching" class="game-table__watching">
          {if @game.knocked_out?, do: "You're Knocked out."} You're watching. {head(@game)}
        </.torn_scrap>
        <.reaction_note waiting?={@waiting?} />
      </div>
    </div>
    """
  end

  attr :seat, :map, required: true
  attr :game, :map, required: true
  attr :compact?, :boolean, required: true
  attr :tappable, :any, required: true
  attr :reaction, :map, default: nil
  attr :since, :integer, default: nil
  attr :now, :integer, required: true

  defp seat(assigns) do
    assigns = assign(assigns, :turn?, assigns.seat.on_turn? and assigns.game.reveal == nil)

    ~H"""
    <li
      id={"seat-#{@seat.person.n}"}
      class={[
        "seat",
        @compact? && "seat--compact",
        @turn? && "is-turn",
        @seat.penalty? && "is-loser",
        @seat.out? && "is-out",
        @since && "is-away"
      ]}
      aria-current={@turn? && "true"}
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
        <.penalty_dice :if={@seat.penalty?} count={@game.reveal.penalty} />
      </span>
      <span :if={!@seat.faces and !@seat.out?} class="seat__dice">
        <b class="seat__n">{@seat.dice}</b>
        <span :for={_ <- 1..@seat.dice//1} class="die is-down"></span>
      </span>
      <small :if={@seat.out?} class="seat__out">out</small>
      <small :if={!@seat.out? && blind_mark(@seat)} class="seat__tag">{blind_mark(@seat)}</small>
      <.away_tag :if={@since} class="seat__away" since={@since} now={@now} />
      <span
        :if={@seat.said && !@game.reveal && (!@compact? || said_now?(@seat, @game))}
        class={["seat__said", said_now?(@seat, @game) && "is-now"]}
      >
        <.bidn count={@seat.said.count} face={@seat.said.face} />
        <em :if={@seat.said.blind?} class="seat__blind">blind</em>
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
      {name(@reveal.loser)}
      <span class="scrap__penalty">
        <b>+{if @reveal.penalty > 1, do: @reveal.penalty}</b>
        <.penalty_dice count={@reveal.penalty} />
      </span>
      <em :if={@reveal.knocked_out?} class="red">Knocked out</em>
    </p>
    <p :if={@reveal.penalty == 2} class="scrap__double">Three sixes counts double.</p>
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
    <p class="faint">
      {name(@game.bid.by)} {verb(@game.bid.by, "bids", "bid")}
      <em :if={@game.bid.blind?} class="scrap__blind">blind</em>
    </p>
    <.bidn count={@game.bid.count} face={@game.bid.face} />
    <p class="faint">{@game.dice_on_table} dice on the table</p>
    """
  end

  attr :count, :integer, required: true
  attr :rest, :global

  defp penalty_dice(assigns) do
    ~H"""
    <span :for={_ <- 1..@count} class="die is-penalty" {@rest}></span>
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

  defp said_now?(seat, game), do: game.bid != nil and game.bid.by == seat.person

  attr :game, :map, required: true
  attr :rolled, :integer, default: nil

  defp my_dice(%{game: %{my_dice: nil}} = assigns) do
    assigns = assign(assigns, :me, hd(assigns.game.seats))

    ~H"""
    <div id="my-dice" class="my-dice" role="group" aria-label="Your dice, blind">
      <span
        :for={i <- 0..(@me.dice - 1)//1}
        id={"my-die-#{@game.round}-#{i}"}
        class={["die is-down", @rolled == @game.round && "is-rolling"]}
        role="img"
        aria-label="face down"
      >
      </span>
      <span class="my-dice__blind">
        <small class="my-dice__mark">blind</small>
        <.block :if={!@game.reveal} id="peek" class="my-dice__peek" phx-click="peek">Peek</.block>
      </span>
    </div>
    """
  end

  defp my_dice(assigns) do
    assigns = assign(assigns, :me, hd(assigns.game.seats))

    ~H"""
    <div id="my-dice" class="my-dice" role="group" aria-label="Your dice">
      <.die
        :for={{face, i} <- Enum.with_index(@game.my_dice)}
        id={"my-die-#{@game.round}-#{i}"}
        face={face}
        data-face={face}
        role="img"
        aria-label={face_word(face)}
        class={[@rolled == @game.round && "is-rolling", counted(face, @game.reveal)]}
      />
      <.penalty_dice
        :if={@me.penalty?}
        count={@game.reveal.penalty}
        role="img"
        aria-label="Penalty die"
      />
      <span :if={blind_mark(@me)} class="my-dice__blind">
        <small class="my-dice__mark">{blind_mark(@me)}</small>
      </span>
    </div>
    """
  end

  defp face_word(face), do: Enum.at(@faces, face - 1)

  defp blind_mark(%{blind?: true}), do: "blind"
  defp blind_mark(%{peeked?: true}), do: "peeked"
  defp blind_mark(_seat), do: nil

  attr :game, :map, required: true
  attr :step, :integer, required: true
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
  attr :away, :map, required: true
  attr :now, :integer, required: true

  def spectators(assigns) do
    assigns =
      assign(assigns, :reactions, unseated_reactions(assigns.spectators, assigns.reactions))

    ~H"""
    <div class="spec">
      <div class="spec__top">
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
        <span :if={!@open? && @reactions != %{}} class="spec__reactions">
          <.reaction :for={{_n, reaction} <- @reactions} reaction={reaction} side? />
        </span>
      </div>
      <ul id="spectators" class="spec__list" hidden={!@open?}>
        <li
          :for={spectator <- @spectators}
          id={"spectator-#{spectator.person.n}"}
          class={@away[spectator.person.n] && "is-away"}
        >
          <.person_tap person={spectator.person} tappable={@tappable}>
            <.person_token person={spectator.person} />
            <span>{name(spectator.person)}</span>
          </.person_tap>
          <small :if={spectator.out?}>out</small>
          <.away_tag
            :if={@away[spectator.person.n]}
            since={@away[spectator.person.n]}
            now={@now}
          />
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

  attr :person, :map, required: true
  attr :since, :integer, required: true
  attr :now, :integer, required: true
  attr :host?, :boolean, required: true

  def turn_away_banner(assigns) do
    ~H"""
    <.sticky_note class="banner">
      <span>
        <b>{@person.nickname}</b> is on turn and away {clock(@now - @since)}. The table waits.
      </span>
      <.block :if={@host?} variant={:walnut} phx-click="remove" phx-value-n={@person.n}>
        Remove {@person.nickname}
      </.block>
      <span :if={!@host?} class="faint">Only the Host can Remove.</span>
    </.sticky_note>
    """
  end

  attr :host, :string, required: true
  attr :away, :map, required: true
  attr :now, :integer, required: true

  def host_away_banner(%{away: %{vote: nil}} = assigns) do
    ~H"""
    <.sticky_note id="host-away" class="banner">
      <span>
        Host <b>{@host}</b> is away {clock(@now - @away.since)}.
        The role passes on in {clock(@away.ends_at - @now)}.
      </span>
      <span :if={too_soon?(@away, @now)}>
        The vote failed. Ask again in {clock(@away.vote_again_at - @now)}.
      </span>
      <.block :if={!too_soon?(@away, @now)} phx-click="pass_host_now">Pass Host now</.block>
    </.sticky_note>
    """
  end

  def host_away_banner(%{away: %{vote: vote}} = assigns) do
    assigns = assign(assigns, vote: vote, left: clock(vote.ends_at - assigns.now))

    ~H"""
    <.sticky_note id="host-away" class="banner">
      <span>
        <b>Pass Host now?</b> {name(@vote.by)} asked. {@vote.yes} of {@vote.of} said yes. {@left} left.
      </span>
      <span :if={@vote.said_yes?} class="faint">You said yes.</span>
      <.block :if={!@vote.said_yes?} phx-click="vote" phx-value-yes="true">Yes</.block>
      <.block :if={!@vote.said_yes?} phx-click="vote" phx-value-yes="false">No</.block>
    </.sticky_note>
    """
  end

  defp too_soon?(%{vote_again_at: at}, now) when is_integer(at), do: now < at
  defp too_soon?(_away, _now), do: false

  attr :since, :integer, required: true
  attr :now, :integer, required: true
  attr :class, :string, default: nil

  def away_tag(assigns) do
    ~H"""
    <small class={@class}>away {clock(@now - @since)}</small>
    """
  end

  defp clock(ms) do
    seconds = max(div(ms, 1000), 0)
    "#{div(seconds, 60)}:#{String.pad_leading("#{rem(seconds, 60)}", 2, "0")}"
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
        class={["reactions__button", !face?(key) && "is-line"]}
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
      class={["reaction", !face?(@reaction.key) && "is-line", @side? && "reaction--side"]}
      role="img"
      aria-label={"#{name(@reaction.by)}: #{reaction_label(@reaction.key)}"}
    >
      {Reaction.text(@reaction.key)}
    </span>
    """
  end

  defp reaction_label(key), do: Map.get(@reaction_labels, key, Reaction.text(key))

  defp face?(key), do: Map.has_key?(@reaction_labels, key)

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
