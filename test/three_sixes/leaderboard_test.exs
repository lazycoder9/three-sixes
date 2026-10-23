defmodule ThreeSixes.LeaderboardTest do
  use ThreeSixes.DataCase, async: false

  alias ThreeSixes.Accounts
  alias ThreeSixes.Accounts.Account
  alias ThreeSixes.Leaderboard
  alias ThreeSixes.Records

  @guest "guest:rival"

  describe "the top rows" do
    test "rank by wins, then by fewer Games, and equal wins and Games share a position" do
      ana = account!("Ana")
      bo = account!("Bo")
      cy = account!("Cy")
      dee = account!("Dee")
      eli = account!("Eli")

      play!(ana, wins: 5, games: 9)
      play!(cy, wins: 3, games: 6)
      play!(bo, wins: 3, games: 4)
      play!(dee, wins: 3, games: 6)
      play!(eli, wins: 1, games: 1)

      assert Leaderboard.top() == [
               %{account_id: ana.id, name: "Ana", games: 9, wins: 5, position: 1},
               %{account_id: bo.id, name: "Bo", games: 4, wins: 3, position: 2},
               %{account_id: cy.id, name: "Cy", games: 6, wins: 3, position: 3},
               %{account_id: dee.id, name: "Dee", games: 6, wins: 3, position: 3},
               %{account_id: eli.id, name: "Eli", games: 1, wins: 1, position: 5}
             ]
    end

    test "list every Account with a finished Game, wins or not, and never a Guest" do
      ana = account!("Ana")
      bo = account!("Bo")
      _idle = account!("Idle")

      play!(ana, wins: 0, games: 2)
      play!(bo, wins: 0, games: 1)

      assert for(row <- Leaderboard.top(), do: {row.account_id, row.position}) ==
               [{bo.id, 1}, {ana.id, 2}]
    end

    test "stop at fifty, cutting through a shared position" do
      accounts = for n <- 1..52, do: account!("P#{n}")
      [last | rest] = Enum.reverse(accounts)

      record!([@guest | for(account <- rest, do: Accounts.person_id(account))])
      play!(last, wins: 0, games: 2)

      top = Leaderboard.top()

      assert length(top) == 50
      assert Enum.all?(top, &(&1.position == 1))
      refute Enum.any?(top, &(&1.account_id == last.id))
    end
  end

  describe "the name on a row" do
    test "is the Nickname, else the first word of the Google name, else the Nickname it last played under" do
      named = account!("Dana", "Dana Scully")
      unnamed = account!(nil, "  Fox William Mulder ")
      nameless = account!(nil, nil)

      for account <- [named, unnamed, nameless], do: play!(account, wins: 1, games: 1)
      record!([@guest, Accounts.person_id(nameless)], "Scully 2", ~U[2026-10-01 09:00:00Z])
      record!([@guest, Accounts.person_id(nameless)], "Scully", ~U[2026-10-03 09:00:00Z])
      record!([@guest, Accounts.person_id(nameless)], "Mulder", ~U[2026-10-02 09:00:00Z])

      names = Map.new(Leaderboard.top(), &{&1.account_id, &1.name})

      assert names[named.id] == "Dana"
      assert names[unnamed.id] == "Fox"
      assert names[nameless.id] == "Scully"
    end
  end

  describe "an Account's own row" do
    test "is its row in the top fifty" do
      ana = account!("Ana")
      bo = account!("Bo")
      play!(ana, wins: 2, games: 2)
      play!(bo, wins: 1, games: 3)

      assert Leaderboard.row(bo.id) ==
               %{account_id: bo.id, name: "Bo", games: 3, wins: 1, position: 2}
    end

    test "has its real position beyond the top fifty" do
      ahead = for n <- 1..55, do: account!("P#{n}")
      me = account!("Me")

      record!([@guest | for(account <- ahead, do: Accounts.person_id(account))])
      play!(me, wins: 0, games: 2)

      assert %{account_id: id, name: "Me", games: 2, wins: 0, position: 56} =
               Leaderboard.row(me.id)

      assert id == me.id
    end

    test "is nothing for an Account with no finished Game" do
      idle = account!("Idle")
      play!(account!("Ana"), wins: 1, games: 1)

      assert Leaderboard.row(idle.id) == nil
    end
  end

  describe "a Guest's standing" do
    test "counts the Guest's Games and Wins, and places them among Accounts by the same rule" do
      ana = account!("Ana")
      bo = account!("Bo")
      cy = account!("Cy")
      dee = account!("Dee")

      play!(ana, wins: 5, games: 9)
      play!(bo, wins: 2, games: 4)
      play!(cy, wins: 2, games: 6)
      play!(dee, wins: 2, games: 7)
      play!("guest:dana", wins: 2, games: 6)

      assert Leaderboard.guest_standing("guest:dana") == %{games: 6, wins: 2, position: 3}
    end

    test "is first on an empty Leaderboard, and first when no Account is ahead" do
      play!("guest:dana", wins: 0, games: 1)

      assert Leaderboard.guest_standing("guest:dana") == %{games: 1, wins: 0, position: 1}

      play!(account!("Ana"), wins: 1, games: 3)
      play!("guest:dana", wins: 1, games: 1)

      assert Leaderboard.guest_standing("guest:dana") == %{games: 2, wins: 1, position: 1}
    end

    test "is nothing for a Guest with no finished Game" do
      play!(account!("Ana"), wins: 1, games: 1)

      assert Leaderboard.guest_standing("guest:dana") == nil
    end
  end

  defp account!(nickname, name \\ nil) do
    n = System.unique_integer([:positive])

    Repo.insert!(%Account{
      google_id: "google:#{n}",
      email: "person#{n}@example.com",
      name: name || nickname,
      nickname: nickname
    })
  end

  defp play!(person, wins: wins, games: games) do
    me = if is_binary(person), do: person, else: Accounts.person_id(person)

    for game <- 1..games//1 do
      if game <= wins, do: record!([me, @guest]), else: record!([@guest, me])
    end
  end

  defp record!(person_ids, nickname \\ nil, finished_at \\ ~U[2026-10-02 20:00:00Z]) do
    {:ok, record} =
      Records.record_game(%{
        room_code: "KQXT",
        rounds: 1,
        finished_at: finished_at,
        placement:
          for {person_id, place} <- Enum.with_index(person_ids, 1) do
            %{person_id: person_id, nickname: nickname || person_id, place: place}
          end,
        checks: []
      })

    record
  end
end
