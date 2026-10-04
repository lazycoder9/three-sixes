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
