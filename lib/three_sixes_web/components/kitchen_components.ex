defmodule ThreeSixesWeb.KitchenComponents do
  use Phoenix.Component
  use ThreeSixesWeb, :verified_routes

  @pips %{
    1 => [4],
    2 => [2, 6],
    3 => [2, 4, 6],
    4 => [0, 2, 6, 8],
    5 => [0, 2, 4, 6, 8],
    6 => [0, 2, 3, 5, 6, 8]
  }

  @turn_to_face %{
    1 => {0, 0},
    2 => {-90, 0},
    3 => {0, -90},
    4 => {0, 90},
    5 => {90, 0},
    6 => {0, 180}
  }

  def logo(assigns) do
    ~H"""
    <.link navigate={~p"/"} class="logo" aria-label="Three Sixes, home">
      3 <small>&times;</small> <.die face={6} />
    </.link>
    """
  end

  attr :variant, :atom, default: :birch, values: [:tomato, :birch, :walnut, :white]
  attr :size, :atom, default: :normal, values: [:normal, :big]
  attr :wide, :boolean, default: false
  attr :type, :string, default: "button"
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(disabled form name value popovertarget popovertargetaction)
  slot :inner_block, required: true

  def block(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "block",
        "block--#{@variant}",
        @size == :big && "block--big",
        @wide && "block--wide",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  attr :letter, :string, required: true
  attr :blank, :boolean, default: false

  def letter_tile(assigns) do
    ~H"""
    <span class={["letter-tile letter-tile--placed", @blank && "letter-tile--blank"]}>{@letter}</span>
    """
  end

  attr :rest, :global, include: ~w(name value maxlength autofocus)

  def letter_tile_input(assigns) do
    ~H"""
    <input
      type="text"
      class="letter-tile"
      autocomplete="off"
      autocapitalize="characters"
      spellcheck="false"
      {@rest}
    />
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, default: nil
  attr :hint, :string, default: nil
  attr :error, :string, default: nil
  attr :rest, :global, include: ~w(name placeholder maxlength autocomplete)

  def write_on_line(assigns) do
    ~H"""
    <div class={["write-on", @error && "is-error"]}>
      <label for={@id}>{@label}</label>
      <input
        type="text"
        id={@id}
        class="write"
        value={@value}
        aria-invalid={@error && "true"}
        {@rest}
      />
      <p :if={@hint} class="hint">{@hint}</p>
      <p :if={@error} class="error" role="alert">{@error}</p>
    </div>
    """
  end

  attr :tape, :atom, default: :center, values: [:center, :corners, :none]
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def notebook_page(assigns) do
    ~H"""
    <div class={["paper", @class]} {@rest}>
      <span :if={@tape == :center} class="tape" aria-hidden="true"></span>
      <span :if={@tape == :corners} class="tape tape--left" aria-hidden="true"></span>
      <span :if={@tape == :corners} class="tape tape--right" aria-hidden="true"></span>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def torn_scrap(assigns) do
    ~H"""
    <div class={["paper paper--scrap", @class]} {@rest}>{render_slot(@inner_block)}</div>
    """
  end

  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def sticky_note(assigns) do
    ~H"""
    <div class={["sticky", @class]} {@rest}>{render_slot(@inner_block)}</div>
    """
  end

  attr :initial, :string, required: true
  attr :color, :atom, default: :tomato, values: [:tomato, :teal, :ochre, :walnut]

  def token(assigns) do
    ~H"""
    <span class={["token", "token--#{@color}"]}>{@initial}</span>
    """
  end

  attr :count, :integer, required: true
  attr :rest, :global

  def tally(assigns) do
    assigns = assign(assigns, fives: div(assigns.count, 5), ones: rem(assigns.count, 5))

    ~H"""
    <span :if={@count > 0} class="tally" role="img" aria-label={wins(@count)} {@rest}>
      <span :for={_ <- 1..@fives//1} class="five"><i :for={_ <- 1..4}></i></span>
      <span :if={@ones > 0}><i :for={_ <- 1..@ones//1}></i></span>
    </span>
    """
  end

  defp wins(1), do: "1 win"
  defp wins(count), do: "#{count} wins"

  attr :face, :integer, required: true, values: 1..6
  attr :class, :any, default: nil
  attr :rest, :global

  def die(assigns) do
    ~H"""
    <span class={["die", @class]} {@rest}><.pips face={@face} /></span>
    """
  end

  @doc """
  Raising `turns` along with a new `face` is what rolls the cube: each turn adds a full tumble
  for the CSS transition to spin through.
  """
  attr :face, :integer, required: true, values: 1..6
  attr :turns, :integer, default: 0
  attr :from, :integer, default: nil, values: [nil | Enum.to_list(1..6)]
  attr :class, :any, default: nil
  attr :rest, :global

  def cube(assigns) do
    ~H"""
    <span class={["cube", @from && "cube--tumble-in", @class]} data-face={@face} {@rest}>
      <span class="cube__tilt">
        <span class="cube__body" style={cube_style(@face, @turns, @from)}>
          <span :for={n <- 1..6} class={"cube__face die f#{n}"}><.pips face={n} /></span>
        </span>
      </span>
    </span>
    """
  end

  defp cube_style(face, turns, from) do
    {x, y} = @turn_to_face[face]
    resting = "--rx: #{x + 720 * turns}deg; --ry: #{y + 1080 * turns}deg"

    case from do
      nil ->
        resting

      from ->
        {fx, fy} = @turn_to_face[from]
        "#{resting}; --from-rx: #{fx}deg; --from-ry: #{fy}deg"
    end
  end

  attr :face, :integer, required: true

  defp pips(assigns) do
    assigns = assign(assigns, :on, @pips[assigns.face])

    ~H"""
    <i :for={cell <- 0..8} class={if cell in @on, do: "on"}></i>
    """
  end
end
