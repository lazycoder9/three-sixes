defmodule ThreeSixesWeb.Layouts do
  use ThreeSixesWeb, :html

  alias ThreeSixesWeb.AuthController

  embed_templates "layouts/*"

  @external_resource theme_script_path = Path.expand("../../../assets/js/theme_boot.js", __DIR__)
  @theme_script theme_script_path |> File.read!() |> String.trim_trailing()

  attr :flash, :map, required: true
  attr :account, :any, required: true, doc: "the signed-in `ThreeSixes.Accounts.Account`, or nil"
  attr :return_to, :any, required: true, doc: "where Sign in comes back to; nil hides Sign in"
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="top">
      <.logo />
      <nav aria-label="Account and settings">
        <button
          id="theme-switch"
          type="button"
          class="round-button"
          phx-hook="ThemeSwitch"
          aria-label="Switch between light and dark"
        >
          <svg viewBox="0 0 20 20" width="18" height="18" aria-hidden="true">
            <circle cx="10" cy="10" r="8" fill="none" stroke="currentColor" stroke-width="2" />
            <path d="M10 2a8 8 0 0 1 0 16z" fill="currentColor" />
          </svg>
        </button>
        <.link
          :if={!@account && @return_to && AuthController.sign_in_available?()}
          navigate={~p"/signin?#{[return_to: @return_to]}"}
        >
          Sign in
        </.link>
        <.link :if={@account} navigate={~p"/account"} class="account-link">
          <.token initial={@account |> account_name() |> String.first() |> String.upcase()} />
          <span>{account_name(@account)}</span>
        </.link>
      </nav>
    </header>

    <main class="table-main">
      {render_slot(@inner_block)}
    </main>

    <.rough_filter />

    <.flash_group flash={@flash} />
    """
  end

  @spec account_name(ThreeSixes.Accounts.Account.t()) :: String.t()
  def account_name(account), do: account.nickname || account.name || account.email

  attr :id, :string, required: true
  attr :code, :string, required: true

  def copy_room_link(assigns) do
    ~H"""
    <div class="copy-link">
      <.block phx-click={JS.dispatch("three-sixes:copy", detail: %{text: url(~p"/r/#{@code}")})}>
        Copy Room link
      </.block>
      <p id={@id} class="copy-link__done" role="status" phx-update="ignore"></p>
    </div>
    """
  end

  attr :flash, :map, required: true
  attr :code, :string, required: true
  attr :sitting_out?, :boolean, required: true
  attr :playing?, :boolean, required: true
  attr :revealing?, :boolean, default: false
  slot :under_code
  slot :inner_block, required: true

  def room(assigns) do
    ~H"""
    <header class="roombar">
      <.logo />
      <div class="roombar__code">
        <span class="tiles" aria-label={"Room code #{@code}"}>
          <.letter_tile :for={letter <- String.graphemes(@code)} letter={letter} />
        </span>
        {render_slot(@under_code)}
      </div>
      <button type="button" class="round-button" popovertarget="room-menu" aria-label="Room menu">
        <svg
          viewBox="0 0 24 24"
          width="20"
          height="20"
          fill="none"
          stroke="currentColor"
          stroke-width="2.6"
          stroke-linecap="round"
          aria-hidden="true"
        >
          <path d="M5 7h14M5 12h14M5 17h14" />
        </svg>
      </button>
    </header>

    <div id="room-menu" class="dialog" popover role="dialog" aria-labelledby="room-menu-title">
      <h2 id="room-menu-title">Room {@code}</h2>
      <div class="stack">
        <.copy_room_link id="menu-copied" code={@code} />
        <.block
          id="menu-sit-out"
          phx-click="sit_out"
          phx-value-sitting_out={to_string(!@sitting_out?)}
        >
          {if @sitting_out?, do: "Sitting out the next Game", else: "Sit out the next Game"}
        </.block>
        <.block id="menu-theme" phx-hook="ThemeSwitch">Light or dark</.block>
      </div>
      <div class="row">
        <.block :if={@playing?} variant={:walnut} popovertarget="leave-dialog">Leave Room</.block>
        <.block :if={!@playing?} variant={:walnut} phx-click="leave">Leave Room</.block>
        <.block popovertarget="room-menu" popovertargetaction="hide">Close</.block>
      </div>
    </div>

    <div
      :if={@playing?}
      id="leave-dialog"
      class="dialog"
      popover
      role="dialog"
      aria-labelledby="leave-dialog-title"
    >
      <h2 id="leave-dialog-title">Leave the Room?</h2>
      <p>
        You'll be Knocked out of this Game{if !@revealing?, do: ", and the Round in play is voided"}.
      </p>
      <div class="row">
        <.block variant={:walnut} phx-click="leave">Leave Room</.block>
        <.block popovertarget="room-menu" popovertargetaction="hide">Stay</.block>
      </div>
    </div>

    <main class="table-main">
      {render_slot(@inner_block)}
    </main>

    <.rough_filter />

    <.flash_group flash={@flash} />
    """
  end

  defp rough_filter(assigns) do
    ~H"""
    <svg class="defs" width="0" height="0" aria-hidden="true">
      <filter id="rough" x="-6%" y="-10%" width="112%" height="120%">
        <feTurbulence type="fractalNoise" baseFrequency=".035" numOctaves="2" seed="3" />
        <feDisplacementMap in="SourceGraphic" scale="2.4" />
      </filter>
    </svg>
    """
  end

  def theme_script(assigns) do
    # The theme must be set before first paint. The tag is built whole so the formatter cannot
    # add whitespace inside it, which would change its CSP hash.
    assigns = assign(assigns, :tag, {:safe, ["<script>", @theme_script, "</script>"]})

    ~H"{@tag}"
  end

  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} class="toasts" aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
      </.flash>
    </div>
    """
  end
end
