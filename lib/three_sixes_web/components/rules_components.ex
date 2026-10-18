defmodule ThreeSixesWeb.RulesComponents do
  use Phoenix.Component

  alias ThreeSixes.Game

  attr :rules, :map, required: true
  attr :host?, :boolean, required: true

  def game_rules(%{host?: true} = assigns) do
    assigns = assign(assigns, :timers, [nil | Game.turn_timers()])

    ~H"""
    <form id="rules-form" class="game-rules" phx-change="rules" phx-auto-recover="ignore">
      <fieldset>
        <legend class="lobby__label">Game rules</legend>
        <div class="game-rules__timers" role="radiogroup" aria-labelledby="turn-timer-label">
          <span class="game-rules__label" id="turn-timer-label">Turn timer</span>
          <label :for={timer <- @timers} class="game-rules__timer">
            <input
              type="radio"
              name="turn_timer"
              value={timer || "off"}
              checked={timer == @rules.turn_timer}
            />
            <span>{if timer, do: "#{timer} s", else: "Off"}</span>
          </label>
        </div>
        <label class="tick">
          <input type="hidden" name="blind_play" value="false" />
          <input type="checkbox" name="blind_play" value="true" checked={@rules.blind_play?} />
          Blind play
        </label>
        <small class="game-rules__hint">Dice arrive face down. Look when you like.</small>
      </fieldset>
    </form>
    """
  end

  def game_rules(assigns) do
    ~H"""
    <div id="rules" class="game-rules">
      <p class="lobby__label">Game rules</p>
      <p class="game-rules__line">{rules_line(@rules)}</p>
      <p :if={@rules.blind_play?} class="game-rules__hint">
        Dice arrive face down. Look when you like.
      </p>
    </div>
    """
  end

  @spec rules_line(Game.rules()) :: String.t()
  def rules_line(rules) do
    timer = if rules.turn_timer, do: "#{rules.turn_timer} s turns", else: "No turn timer"
    if rules.blind_play?, do: "#{timer} · blind play", else: timer
  end
end
