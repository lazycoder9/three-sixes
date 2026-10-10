defmodule ThreeSixes.Accounts do
  import Ecto.Query

  alias ThreeSixes.Accounts.Account
  alias ThreeSixes.Accounts.GuestMerge
  alias ThreeSixes.Records.CheckRecord
  alias ThreeSixes.Records.Placement
  alias ThreeSixes.Repo
  alias ThreeSixes.Room

  @type stats :: %{
          games: non_neg_integer(),
          wins: non_neg_integer(),
          win_rate: 0..100 | nil,
          average_placement: float() | nil,
          checks_won: non_neg_integer(),
          bluffs_caught: non_neg_integer()
        }
  @type recent_game :: %{
          finished_at: DateTime.t(),
          place: pos_integer(),
          players: [%{nickname: String.t(), place: pos_integer(), me?: boolean()}]
        }

  @spec get_account(term()) :: Account.t() | nil
  def get_account(id), do: Repo.get(Account, id)

  @spec person_id(Account.t()) :: Room.person_id()
  def person_id(%Account{id: id}), do: "account:#{id}"

  @spec guest_person_id(String.t()) :: Room.person_id()
  def guest_person_id(guest_id), do: "guest:" <> guest_id

  @spec find_or_create_from_google(Ueberauth.Auth.t()) ::
          {:ok, Account.t()} | {:error, Ecto.Changeset.t()}
  def find_or_create_from_google(%{uid: uid, info: info}) do
    find_or_create(
      %{
        google_id: to_string(uid),
        name: info.name,
        email: info.email,
        avatar_url: info.image
      },
      info.first_name || first_word(info.name)
    )
  end

  @spec find_or_create_dev(String.t()) :: {:ok, Account.t()} | {:error, Ecto.Changeset.t()}
  def find_or_create_dev(name) do
    find_or_create(
      %{
        google_id: "dev:" <> String.downcase(name),
        name: name,
        email: (name |> String.downcase() |> String.replace(~r/\s/u, "")) <> "@dev.localhost"
      },
      name
    )
  end

  @spec save_nickname(Account.t(), String.t()) ::
          {:ok, Account.t()} | {:error, Ecto.Changeset.t()}
  def save_nickname(account, nickname) do
    account
    |> Account.nickname_changeset(nickname)
    |> Repo.update()
  end

  @spec stats(Room.person_id()) :: stats()
  def stats(person_id) do
    {games, wins, places} =
      Repo.one(
        from p in Placement,
          where: p.person_id == ^person_id,
          select: {count(p.id), filter(count(p.id), p.place == 1), sum(p.place)}
      )

    {checks_won, bluffs_caught} =
      Repo.one(
        from c in CheckRecord,
          where: not c.stood and (c.checker_id == ^person_id or c.bidder_id == ^person_id),
          select:
            {filter(count(c.id), c.checker_id == ^person_id),
             filter(count(c.id), c.bidder_id == ^person_id)}
      )

    %{
      games: games,
      wins: wins,
      win_rate: if(games > 0, do: round(wins * 100 / games)),
      average_placement: if(games > 0, do: Float.round(places / games, 1)),
      checks_won: checks_won,
      bluffs_caught: bluffs_caught
    }
  end

  @spec recent_games(Room.person_id(), pos_integer()) :: [recent_game()]
  def recent_games(person_id, limit \\ 10) do
    mine =
      from p in Placement,
        join: g in assoc(p, :game_record),
        where: p.person_id == ^person_id,
        order_by: [desc: g.finished_at, desc: g.id],
        limit: ^limit,
        select: %{game_record_id: g.id, finished_at: g.finished_at, place: p.place}

    games = Repo.all(mine)
    ids = Enum.map(games, & &1.game_record_id)

    players =
      from(p in Placement, where: p.game_record_id in ^ids, order_by: p.place)
      |> Repo.all()
      |> Enum.group_by(
        & &1.game_record_id,
        &%{nickname: &1.nickname, place: &1.place, me?: &1.person_id == person_id}
      )

    for game <- games do
      %{finished_at: game.finished_at, place: game.place, players: players[game.game_record_id]}
    end
  end

  @spec take_over_guest(Room.person_id(), Account.t()) :: {:ok, :merged | :already_merged}
  def take_over_guest(guest_person_id, account) do
    now = DateTime.utc_now(:second)
    merge = %{guest_id: guest_person_id, account_id: account.id, inserted_at: now}

    Repo.transaction(fn ->
      case Repo.insert_all(GuestMerge, [merge], on_conflict: :nothing) do
        {1, _} -> move_history(guest_person_id, person_id(account))
        {0, _} -> :already_merged
      end
    end)
  end

  defp move_history(guest, me) do
    shared = from p in Placement, where: p.person_id == ^me, select: p.game_record_id

    # Placements move last: until then they tell the shared Games apart.
    for {schema, column} <- [
          {CheckRecord, :checker_id},
          {CheckRecord, :bidder_id},
          {Placement, :person_id}
        ] do
      from(r in schema,
        where: field(r, ^column) == ^guest and r.game_record_id not in subquery(shared)
      )
      |> Repo.update_all(set: [{column, me}])
    end

    :merged
  end

  defp find_or_create(attrs, first_name) do
    case Repo.get_by(Account, google_id: attrs.google_id) do
      nil ->
        %Account{nickname: first_nickname(first_name)}
        |> Account.google_changeset(attrs)
        |> Repo.insert()

      account ->
        account
        |> Account.google_changeset(attrs)
        |> Repo.update()
    end
  end

  defp first_word(nil), do: nil
  defp first_word(name), do: name |> String.split() |> List.first()

  defp first_nickname(nil), do: nil

  defp first_nickname(name) do
    case name |> String.trim() |> String.slice(0, Room.max_nickname_length()) |> String.trim() do
      "" -> nil
      nickname -> nickname
    end
  end
end
