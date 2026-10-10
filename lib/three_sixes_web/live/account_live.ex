defmodule ThreeSixesWeb.AccountLive do
  use ThreeSixesWeb, :live_view

  alias ThreeSixes.Accounts

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns.account do
      {:ok,
       assign(socket,
         page_title: Layouts.account_name(socket.assigns.account),
         stats: Accounts.stats(socket.assigns.person_id),
         games: Accounts.recent_games(socket.assigns.person_id)
       )}
    else
      {:ok, push_navigate(socket, to: ~p"/signin?#{[return_to: ~p"/account"]}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} account={@account} return_to={~p"/account"}>
      <section class="screen account">
        <h1 class="headline">{Layouts.account_name(@account)}</h1>
        <p class="lede">Signed in with Google as {@account.email}</p>
        <div class="sheets">
          <.notebook_page tape={:center}>
            <h2>The score so far</h2>
            <dl class="score">
              <div>
                <dt>Games</dt>
                <dd>{@stats.games}</dd>
              </div>
              <div>
                <dt>Wins</dt>
                <dd><.tally count={@stats.wins} />{@stats.wins}</dd>
              </div>
              <div>
                <dt>Win rate</dt>
                <dd>{if @stats.win_rate, do: "#{@stats.win_rate}%", else: "–"}</dd>
              </div>
              <div>
                <dt>Average Placement</dt>
                <dd>{@stats.average_placement || "–"}</dd>
              </div>
              <div>
                <dt>Checks won</dt>
                <dd>{@stats.checks_won}</dd>
              </div>
              <div>
                <dt>Bluffs caught</dt>
                <dd>{@stats.bluffs_caught}</dd>
              </div>
            </dl>
          </.notebook_page>
          <.notebook_page tape={:corners}>
            <h2>Recent Games</h2>
            <ol :if={@games != []} class="games">
              <li :for={game <- @games}>
                <time datetime={game.finished_at |> DateTime.to_date() |> Date.to_iso8601()}>
                  {Calendar.strftime(game.finished_at, "%b %-d")}
                </time>
                <span class="rank">
                  <span class={game.place == 1 && "circled"}>{ordinal(game.place)}</span>
                  <small>of {length(game.players)}</small>
                </span>
                <span class="order">
                  <span :for={player <- game.players}>
                    {player.place}. <span class={player.me? && "hl"}>{player.nickname}</span>
                  </span>
                </span>
              </li>
            </ol>
            <p :if={@games == []} class="faint">
              This list fills in after your first finished Game.
            </p>
          </.notebook_page>
        </div>
        <p class="account__foot">
          <.link href={~p"/auth/logout"} method="delete" class="block block--birch">Log out</.link>
        </p>
      </section>
    </Layouts.app>
    """
  end

  @spec ordinal(pos_integer()) :: String.t()
  def ordinal(place) do
    suffix =
      case {rem(place, 100), rem(place, 10)} do
        {teen, _} when teen in 11..13 -> "th"
        {_, 1} -> "st"
        {_, 2} -> "nd"
        {_, 3} -> "rd"
        _ -> "th"
      end

    "#{place}#{suffix}"
  end
end
