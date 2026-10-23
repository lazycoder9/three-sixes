defmodule ThreeSixes.Leaderboard do
  import Ecto.Query

  alias ThreeSixes.Accounts.Account
  alias ThreeSixes.Records.Placement
  alias ThreeSixes.Repo

  @size 50

  @type row :: %{
          account_id: pos_integer(),
          name: String.t(),
          games: pos_integer(),
          wins: non_neg_integer(),
          position: pos_integer()
        }

  @spec top() :: [row()]
  def top do
    board()
    |> limit(@size)
    |> Repo.all()
    |> Enum.map(&to_row/1)
  end

  @spec row(pos_integer()) :: row() | nil
  def row(account_id) do
    board()
    |> where([standing: s], s.account_id == ^account_id)
    |> Repo.one()
    |> then(&(&1 && to_row(&1)))
  end

  defp board do
    from s in subquery(positioned()),
      as: :standing,
      order_by: [asc: s.position, asc: s.account_id],
      select: %{
        account_id: s.account_id,
        nickname: s.nickname,
        google_name: s.google_name,
        last_nickname: subquery(last_nickname()),
        games: s.games,
        wins: s.wins,
        position: s.position
      }
  end

  defp positioned do
    standings =
      from p in Placement,
        join: a in Account,
        on: p.person_id == fragment("'account:' || ?", a.id),
        group_by: a.id,
        select: %{
          account_id: a.id,
          person_id: p.person_id,
          nickname: a.nickname,
          google_name: a.name,
          games: count(p.id),
          wins: filter(count(p.id), p.place == 1)
        }

    from s in subquery(standings),
      windows: [standing: [order_by: [desc: s.wins, asc: s.games]]],
      select: %{s | position: over(rank(), :standing)}
  end

  defp last_nickname do
    from p in Placement,
      join: g in assoc(p, :game_record),
      where: p.person_id == parent_as(:standing).person_id,
      order_by: [desc: g.finished_at, desc: g.id],
      limit: 1,
      select: p.nickname
  end

  defp to_row(standing) do
    %{
      account_id: standing.account_id,
      name: standing.nickname || first_word(standing.google_name) || standing.last_nickname,
      games: standing.games,
      wins: standing.wins,
      position: standing.position
    }
  end

  defp first_word(nil), do: nil
  defp first_word(name), do: name |> String.split() |> List.first()
end
