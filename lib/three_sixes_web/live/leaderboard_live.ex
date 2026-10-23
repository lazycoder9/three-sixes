defmodule ThreeSixesWeb.LeaderboardLive do
  use ThreeSixesWeb, :live_view

  import ThreeSixesWeb.AccountLive, only: [ordinal: 1]

  alias ThreeSixes.Leaderboard
  alias ThreeSixesWeb.AuthController

  @impl true
  def mount(_params, _session, socket) do
    rows = Leaderboard.top()
    account = socket.assigns.account
    my_id = account && account.id

    {:ok,
     assign(socket,
       page_title: "Leaderboard",
       rows: rows,
       my_id: my_id,
       slip: slip(account, socket.assigns.person_id, rows)
     )}
  end

  defp slip(nil, person_id, _rows) do
    if AuthController.sign_in_available?() do
      case Leaderboard.guest_standing(person_id) do
        nil -> :sign_in
        standing -> {:guest, standing}
      end
    end
  end

  defp slip(account, _person_id, rows) do
    if !Enum.any?(rows, &(&1.account_id == account.id)) do
      case Leaderboard.row(account.id) do
        nil -> :no_games
        row -> {:row, row}
      end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} account={@account} return_to={~p"/leaderboard"}>
      <section class="screen leaderboard">
        <h1 class="headline">Leaderboard</h1>
        <p class="lede">Games won by every Account, across every Room.</p>

        <.notebook_page tape={:corners} class="leaderboard__sheet">
          <table :if={@rows != []} id="leaderboard" class="standings">
            <.columns />
            <thead>
              <tr>
                <th scope="col"><span class="sr-only">Position</span></th>
                <th scope="col">Nickname</th>
                <th scope="col">Games</th>
                <th scope="col">Wins</th>
              </tr>
            </thead>
            <tbody>
              <.standing :for={row <- @rows} row={row} me?={row.account_id == @my_id} />
            </tbody>
          </table>
          <p :if={@rows == []} class="faint">Nobody is on the Leaderboard yet.</p>

          <div :if={@slip} id="my-standing" class="slip">
            <div class="slip__paper">
              <%= case @slip do %>
                <% {:row, row} -> %>
                  <table class="standings" aria-label="Your place on the Leaderboard">
                    <.columns />
                    <tbody><.standing row={row} me?={true} /></tbody>
                  </table>
                <% :sign_in -> %>
                  <.link
                    navigate={~p"/signin?#{[return_to: ~p"/leaderboard"]}"}
                    class="slip__note"
                  >
                    Sign in to get on the Leaderboard
                  </.link>
                <% {:guest, standing} -> %>
                  <p class="slip__note slip__note--guest">
                    You've finished {games(standing.games)} on this device, but Guests aren't on the Leaderboard.
                    <.link navigate={~p"/signin?#{[return_to: ~p"/leaderboard"]}"}>Sign in</.link>
                    and {if standing.games == 1, do: "it moves", else: "they move"} to your Account.
                    That's enough for {ordinal(standing.position)} place.
                  </p>
                <% :no_games -> %>
                  <p class="slip__note">Finish a Game to get on the Leaderboard.</p>
              <% end %>
            </div>
          </div>
        </.notebook_page>
      </section>
    </Layouts.app>
    """
  end

  @spec games(pos_integer()) :: String.t()
  def games(1), do: "1 Game"
  def games(count), do: "#{count} Games"

  defp columns(assigns) do
    ~H"""
    <colgroup>
      <col class="standings__position" />
      <col />
      <col class="standings__games" />
      <col class="standings__wins" />
    </colgroup>
    """
  end

  attr :row, :map, required: true
  attr :me?, :boolean, required: true

  defp standing(assigns) do
    ~H"""
    <tr class={@me? && "is-me"}>
      <td class="standings__position">
        <span class={@row.position <= 3 && "circled"}>{ordinal(@row.position)}</span>
        <.crown :if={@row.position == 1} />
      </td>
      <td>
        <span class="standings__name"><span>{@row.name}</span> <em :if={@me?}>← you</em></span>
      </td>
      <td class="standings__games"><small>{@row.games}</small></td>
      <td class="standings__wins">{@row.wins}</td>
    </tr>
    """
  end

  defp crown(assigns) do
    ~H"""
    <svg class="crown" viewBox="0 0 28 20" width="28" height="20" aria-hidden="true">
      <path class="crown__fill" d="M4 16.5 3 6l6.5 5.5L14 3l4.5 8.5L25 6l-1 10.5z" />
      <path d="M4 16.5 3 6l6.5 5.5L14 3l4.5 8.5L25 6l-1 10.5z M4.2 14.2c6.5-.8 13-.7 19.6.2" />
      <circle cx="3" cy="5" r="1.4" />
      <circle cx="14" cy="2.2" r="1.4" />
      <circle cx="25" cy="5" r="1.4" />
    </svg>
    """
  end
end
