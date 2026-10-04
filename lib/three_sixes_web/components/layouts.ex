defmodule ThreeSixesWeb.Layouts do
  use ThreeSixesWeb, :html

  embed_templates "layouts/*"

  @external_resource theme_script_path = Path.expand("../../../assets/js/theme_boot.js", __DIR__)
  @theme_script theme_script_path |> File.read!() |> String.trim_trailing()

  attr :flash, :map, required: true
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="top">
      <.logo />
      <nav aria-label="Page settings">
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
      </nav>
    </header>

    <main class="table-main">
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end

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
  slot :inner_block, required: true

  def room(assigns) do
    ~H"""
    <header class="roombar">
      <.logo />
      <span class="tiles roombar__code" aria-label={"Room code #{@code}"}>
        <.letter_tile :for={letter <- String.graphemes(@code)} letter={letter} />
      </span>
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
        <.block id="menu-theme" phx-hook="ThemeSwitch">Light or dark</.block>
      </div>
      <div class="row">
        <.block popovertarget="room-menu" popovertargetaction="hide">Close</.block>
      </div>
    </div>

    <main class="table-main">
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
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
