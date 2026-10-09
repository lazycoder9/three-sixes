defmodule ThreeSixesWeb.KitLive do
  use ThreeSixesWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Kitchen Table kit")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} account={nil} return_to={nil}>
      <div class="kit-panels">
        <section
          :for={theme <- ~w(light dark)}
          data-theme={theme}
          class="wood kit-panel"
          aria-label={"#{theme} theme"}
        >
          <h1 class="headline">{String.capitalize(theme)}</h1>

          <div class="kit-row">
            <.logo />
            <.token initial="T" color={:tomato} />
            <.token initial="D" color={:teal} />
            <.token initial="M" color={:ochre} />
            <.token initial="A" color={:walnut} />
          </div>

          <div class="kit-row">
            <.block variant={:tomato}>Create a Room</.block>
            <.block>Join</.block>
            <.block variant={:walnut}>Log out</.block>
            <.block variant={:white}>Sign in with Google</.block>
            <.block variant={:tomato} size={:big}>Create a Room</.block>
            <.block variant={:tomato} disabled>Join Room</.block>
          </div>

          <div class="kit-row">
            <div class="tiles">
              <.letter_tile letter="K" />
              <.letter_tile letter="Q" />
              <.letter_tile letter="X" />
              <.letter_tile letter="T" />
            </div>
            <div class="tiles">
              <.letter_tile :for={letter <- ~w(G O N E)} letter={letter} blank />
            </div>
            <div class="tiles">
              <.letter_tile_input aria-label={"#{theme} kit, letter 1"} maxlength="1" />
              <.letter_tile_input aria-label={"#{theme} kit, letter 2"} maxlength="1" />
            </div>
          </div>

          <div class="kit-row">
            <.die :for={face <- 1..6} face={face} />
          </div>

          <div class="kit-row">
            <.cube :for={face <- [1, 5, 6]} face={face} />
          </div>

          <div class="kit-row kit-row--paper">
            <.notebook_page>
              <h2>Notebook page</h2>
              <.write_on_line
                id={"#{theme}-nickname"}
                label="Your Nickname"
                value="Dana"
                hint="Filled in from your Account."
              />
            </.notebook_page>
            <.notebook_page tape={:corners}>
              <.write_on_line
                id={"#{theme}-nickname-error"}
                label="Your Nickname"
                placeholder="write it here"
                error="Pick a Nickname first."
              />
            </.notebook_page>
          </div>

          <div class="kit-row kit-row--paper">
            <.torn_scrap>
              <b>Torn scrap</b> Say how many of one face are on the whole table.
            </.torn_scrap>
            <.sticky_note>
              <h2>Sticky note</h2>
              <p>Sign in, dialogs and toasts.</p>
            </.sticky_note>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
