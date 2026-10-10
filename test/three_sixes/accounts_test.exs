defmodule ThreeSixes.AccountsTest do
  use ThreeSixes.DataCase, async: false

  alias ThreeSixes.Accounts
  alias ThreeSixes.Accounts.Account
  alias ThreeSixes.Records

  defp google(uid, info) do
    %Ueberauth.Auth{
      uid: uid,
      provider: :google,
      info:
        struct(
          Ueberauth.Auth.Info,
          Map.merge(
            %{
              name: "Dana Scully",
              first_name: "Dana",
              email: "dana@example.com",
              image: "https://example.com/dana.png"
            },
            info
          )
        )
    }
  end

  describe "an Account from a Google sign-in" do
    test "is created with Google's details, and its first Nickname is the first name" do
      assert {:created, %Account{} = account} =
               Accounts.find_or_create_from_google(google("1001", %{}))

      assert account.google_id == "1001"
      assert account.name == "Dana Scully"
      assert account.email == "dana@example.com"
      assert account.avatar_url == "https://example.com/dana.png"
      assert account.nickname == "Dana"
      assert Accounts.get_account(account.id) == account
    end

    test "takes the first word of the name for the Nickname when Google gives no first name" do
      {:created, account} =
        Accounts.find_or_create_from_google(google(1002, %{first_name: nil, name: "Fox Mulder"}))

      assert account.google_id == "1002"
      assert account.nickname == "Fox"
    end

    test "cuts the first Nickname to 16 characters and trims it" do
      {:created, account} =
        Accounts.find_or_create_from_google(
          google("1003", %{first_name: "  Bartholomew-Alexander  "})
        )

      assert account.nickname == "Bartholomew-Alex"
    end

    test "has no Nickname when Google gives no name at all" do
      {:created, account} =
        Accounts.find_or_create_from_google(google("1004", %{first_name: nil, name: nil}))

      assert account.nickname == nil
    end

    test "is found again by the same Google id, with name, email and avatar refreshed and the Nickname kept" do
      {:created, first} = Accounts.find_or_create_from_google(google("1005", %{}))
      {:ok, _renamed} = Accounts.save_nickname(first, "Agent D")

      {:found, again} =
        Accounts.find_or_create_from_google(
          google("1005", %{
            name: "Dana Katherine Scully",
            first_name: "Katherine",
            email: "dks@example.com",
            image: "https://example.com/dks.png"
          })
        )

      assert again.id == first.id
      assert again.name == "Dana Katherine Scully"
      assert again.email == "dks@example.com"
      assert again.avatar_url == "https://example.com/dks.png"
      assert again.nickname == "Agent D"
    end

    test "says whether this sign-in created it" do
      assert {:created, account} = Accounts.find_or_create_from_google(google("1008", %{}))
      assert {:found, again} = Accounts.find_or_create_from_google(google("1008", %{}))
      assert again.id == account.id
    end

    test "may share its email with another Account" do
      {:created, one} = Accounts.find_or_create_from_google(google("1006", %{}))
      {:created, other} = Accounts.find_or_create_from_google(google("1007", %{}))

      assert one.id != other.id
      assert one.email == other.email
    end
  end

  describe "a dev Account" do
    test "is made from a name, and the same name finds it again" do
      assert {:created, account} = Accounts.find_or_create_dev("Dana Scully")

      assert account.google_id == "dev:dana scully"
      assert account.email == "danascully@dev.localhost"
      assert account.name == "Dana Scully"
      assert account.nickname == "Dana Scully"

      assert {:found, %Account{id: id}} = Accounts.find_or_create_dev("dana scully")
      assert id == account.id
    end
  end

  describe "saving a Nickname" do
    setup do
      {:created, account} = Accounts.find_or_create_dev("Dana")
      %{account: account}
    end

    test "keeps it trimmed", %{account: account} do
      assert {:ok, saved} = Accounts.save_nickname(account, "  Queen of Dice ")
      assert saved.nickname == "Queen of Dice"
      assert Accounts.get_account(account.id).nickname == "Queen of Dice"
    end

    test "takes 1 to 16 characters, like a Room", %{account: account} do
      assert {:ok, %Account{nickname: "Sixteen chars ok"}} =
               Accounts.save_nickname(account, "Sixteen chars ok")

      assert {:error, _} = Accounts.save_nickname(account, "Seventeen chars!!")
      assert {:error, _} = Accounts.save_nickname(account, "   ")
      assert Accounts.get_account(account.id).nickname == "Sixteen chars ok"
    end
  end

  defp record!(players, checks, finished_at \\ ~U[2026-10-02 20:00:00.000000Z]) do
    {:ok, record} =
      Records.record_game(%{
        room_code: "KQXT",
        rounds: 3,
        finished_at: finished_at,
        placement:
          players
          |> Enum.with_index(1)
          |> Enum.map(fn {{person_id, nickname}, place} ->
            %{person_id: person_id, nickname: nickname, place: place}
          end),
        checks:
          checks
          |> Enum.with_index(1)
          |> Enum.map(fn {{checker, bidder, stood?}, round} ->
            %{round: round, checker: checker, bidder: bidder, stood?: stood?}
          end)
      })

    record
  end

  @me "guest:me"
  @ana "guest:ana"
  @bo "guest:bo"

  defp three_games do
    record!(
      [{@me, "Malika"}, {@ana, "Ana"}, {@bo, "Bo"}],
      [{@me, @ana, false}, {@ana, @me, true}],
      ~U[2026-10-01 20:00:00.000000Z]
    )

    record!(
      [{@bo, "Bo"}, {@me, "Malika 2"}, {@ana, "Ana"}],
      [{@me, @bo, false}, {@bo, @ana, false}],
      ~U[2026-10-03 20:00:00.000000Z]
    )

    record!(
      [{@ana, "Ana"}, {@me, "Malika"}],
      [{@me, @ana, true}, {@ana, @me, false}],
      ~U[2026-10-02 20:00:00.000000Z]
    )
  end

  describe "the stats" do
    test "count each person's own Games, wins, Checks won and Bluffs caught" do
      three_games()

      assert Accounts.stats(@me) == %{
               games: 3,
               wins: 1,
               win_rate: 33,
               average_placement: 1.7,
               checks_won: 2,
               bluffs_caught: 1
             }

      assert Accounts.stats(@ana) == %{
               games: 3,
               wins: 1,
               win_rate: 33,
               average_placement: 2.0,
               checks_won: 1,
               bluffs_caught: 2
             }

      assert %{games: 2, wins: 1, win_rate: 50, average_placement: 2.0} = Accounts.stats(@bo)
    end

    test "with no Games are nothing, with no win rate or average Placement" do
      record!([{@ana, "Ana"}, {@bo, "Bo"}], [{@ana, @bo, false}])

      assert Accounts.stats(@me) == %{
               games: 0,
               wins: 0,
               win_rate: nil,
               average_placement: nil,
               checks_won: 0,
               bluffs_caught: 0
             }
    end
  end

  describe "the recent Games" do
    test "are the person's Games newest first, each with their place and the full Placement" do
      three_games()

      assert Accounts.recent_games(@me) == [
               %{
                 finished_at: ~U[2026-10-03 20:00:00.000000Z],
                 place: 2,
                 players: [
                   %{nickname: "Bo", place: 1, me?: false},
                   %{nickname: "Malika 2", place: 2, me?: true},
                   %{nickname: "Ana", place: 3, me?: false}
                 ]
               },
               %{
                 finished_at: ~U[2026-10-02 20:00:00.000000Z],
                 place: 2,
                 players: [
                   %{nickname: "Ana", place: 1, me?: false},
                   %{nickname: "Malika", place: 2, me?: true}
                 ]
               },
               %{
                 finished_at: ~U[2026-10-01 20:00:00.000000Z],
                 place: 1,
                 players: [
                   %{nickname: "Malika", place: 1, me?: true},
                   %{nickname: "Ana", place: 2, me?: false},
                   %{nickname: "Bo", place: 3, me?: false}
                 ]
               }
             ]

      assert [%{place: 1}, %{place: 3}] = Accounts.recent_games(@bo)
    end

    test "are the last ten by default, or as many as asked" do
      for day <- 1..12 do
        record!(
          [{@me, "Malika"}, {@ana, "Ana"}],
          [],
          DateTime.new!(Date.new!(2026, 9, day), ~T[12:00:00.000000])
        )
      end

      recent = Accounts.recent_games(@me)

      assert length(recent) == 10
      assert hd(recent).finished_at.day == 12
      assert List.last(recent).finished_at.day == 3
      assert @me |> Accounts.recent_games(2) |> Enum.map(& &1.finished_at.day) == [12, 11]
      assert Accounts.recent_games(@bo) == []
    end
  end

  describe "taking over a Guest's history" do
    setup do
      {:created, account} = Accounts.find_or_create_dev("Malika")
      %{account: account, me: Accounts.person_id(account)}
    end

    test "moves the Guest's Placements and both sides of their Checks to the Account",
         %{account: account, me: me} do
      record!([{"guest:g1", "Malika"}, {@ana, "Ana"}], [
        {"guest:g1", @ana, false},
        {@ana, "guest:g1", false}
      ])

      record!([{@ana, "Ana"}, {"guest:g1", "Mal"}], [{@ana, "guest:g1", true}])

      assert Accounts.take_over_guest("guest:g1", account) == {:ok, :merged}

      assert Accounts.stats(me) == %{
               games: 2,
               wins: 1,
               win_rate: 50,
               average_placement: 1.5,
               checks_won: 1,
               bluffs_caught: 1
             }

      assert %{games: 0, checks_won: 0, bluffs_caught: 0} = Accounts.stats("guest:g1")
      assert %{games: 2, checks_won: 1, bluffs_caught: 1} = Accounts.stats(@ana)
      assert [%{players: [_, %{nickname: "Mal", me?: true}]}, _] = Accounts.recent_games(me)
    end

    test "merges a Guest id only once, even after it plays another Game",
         %{account: account, me: me} do
      record!([{"guest:g1", "Malika"}, {@ana, "Ana"}], [])
      {:ok, :merged} = Accounts.take_over_guest("guest:g1", account)
      record!([{"guest:g1", "Malika"}, {@ana, "Ana"}], [{@ana, "guest:g1", false}])

      assert Accounts.take_over_guest("guest:g1", account) == {:ok, :already_merged}

      assert %{games: 1, bluffs_caught: 0} = Accounts.stats(me)
      assert %{games: 1, bluffs_caught: 1} = Accounts.stats("guest:g1")
    end

    test "is refused to a second Account once one has taken the Guest id", %{account: account} do
      record!([{"guest:g1", "Malika"}, {@ana, "Ana"}], [])
      {:created, other} = Accounts.find_or_create_dev("Bo")
      {:ok, :merged} = Accounts.take_over_guest("guest:g1", account)

      assert Accounts.take_over_guest("guest:g1", other) == {:ok, :already_merged}

      assert %{games: 0} = Accounts.stats(Accounts.person_id(other))
      assert %{games: 1} = Accounts.stats(Accounts.person_id(account))
    end

    test "in a Game the Guest and the Account both played keeps only the Account's record",
         %{account: account, me: me} do
      record!(
        [{"guest:g1", "Malika"}, {me, "Malika 2"}],
        [{"guest:g1", me, false}, {me, "guest:g1", true}]
      )

      record!([{@ana, "Ana"}, {"guest:g1", "Malika"}], [
        {"guest:g1", @ana, false},
        {@ana, "guest:g1", false}
      ])

      assert {:ok, :merged} = Accounts.take_over_guest("guest:g1", account)

      assert Accounts.stats(me) == %{
               games: 2,
               wins: 0,
               win_rate: 0,
               average_placement: 2.0,
               checks_won: 1,
               bluffs_caught: 2
             }

      assert %{games: 1, wins: 1} = Accounts.stats("guest:g1")

      assert [
               _,
               %{players: [%{nickname: "Malika", me?: false}, %{nickname: "Malika 2", me?: true}]}
             ] =
               Accounts.recent_games(me)
    end
  end

  describe "a person id" do
    test "is the Account's id or the Guest's id, each marked as which" do
      {:created, account} = Accounts.find_or_create_dev("Malika")

      assert Accounts.person_id(account) == "account:#{account.id}"
      assert Accounts.guest_person_id("g1") == "guest:g1"
    end
  end

  test "an unknown Account id finds nothing" do
    assert Accounts.get_account(-1) == nil
  end
end
