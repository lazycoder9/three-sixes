defmodule ThreeSixes.RoomTest do
  use ExUnit.Case, async: true

  alias ThreeSixes.Room

  @host "guest:host"

  defp room, do: Room.new("KQXT", @host)

  defp enter!(room, person_id, nickname) do
    {:ok, room} = Room.enter(room, person_id, nickname)
    room
  end

  defp lobby do
    room()
    |> enter!("guest:timur", "Timur")
    |> enter!(@host, "Malika")
    |> enter!("guest:dana", "Dana")
  end

  defp playing do
    {:ok, room} = Room.start_game(lobby(), @host, ["guest:dana", "guest:timur", @host])
    Room.start_round(room, %{"guest:dana" => [6], "guest:timur" => [2], @host => [6]})
  end

  test "a person who enters a Nickname becomes a member, the Nickname trimmed" do
    room = room()
    refute Room.member?(room, "guest:dana")

    room = enter!(room, "guest:dana", "  Dana  ")

    assert Room.member?(room, "guest:dana")
    assert Room.view_for(room, "guest:dana").me == "Dana"
  end

  test "an empty or whitespace-only Nickname is blank" do
    assert Room.enter(room(), "guest:dana", "") == {:error, :blank}
    assert Room.enter(room(), "guest:dana", "   \t ") == {:error, :blank}
  end

  test "a Nickname that is not text is blank" do
    assert Room.enter(room(), "guest:dana", nil) == {:error, :blank}
    assert Room.enter(room(), "guest:dana", %{"a" => "b"}) == {:error, :blank}
  end

  test "a Nickname is at most 16 characters, counted as the eye reads them" do
    assert {:ok, _} = Room.enter(room(), "guest:dana", String.duplicate("a", 16))
    assert Room.enter(room(), "guest:dana", String.duplicate("a", 17)) == {:error, :too_long}
    assert {:ok, _} = Room.enter(room(), "guest:dana", String.duplicate("é", 16))
    assert {:ok, _} = Room.enter(room(), "guest:dana", "  " <> String.duplicate("a", 16) <> "  ")
  end

  test "a Nickname taken regardless of case names who holds it and suggests the next number" do
    room = enter!(room(), "guest:dana", "Dana")

    assert Room.enter(room, "guest:other", "dana") == {:taken, "Dana", "Dana 2"}
    refute Room.member?(room, "guest:other")
  end

  test "when the numbered Nickname is taken too, the suggestion is the next number" do
    room =
      room()
      |> enter!("guest:dana", "Dana")
      |> enter!("guest:dana2", "dana 2")

    assert Room.enter(room, "guest:other", "DANA") == {:taken, "Dana", "Dana 3"}
  end

  test "a numbered Nickname that is taken gets the next number, not a second number" do
    room =
      room()
      |> enter!("guest:dana", "Dana")
      |> enter!("guest:dana2", "Dana 2")

    assert Room.enter(room, "guest:other", "dana 2") == {:taken, "Dana 2", "Dana 3"}
  end

  test "a suggestion for a long Nickname cuts the name so the whole fits 16 characters" do
    fifteen = "Alexandrovichka"
    sixteen = "Alexandrovichkas"
    room = room() |> enter!("guest:a", fifteen) |> enter!("guest:b", sixteen)

    assert Room.enter(room, "guest:c", fifteen) == {:taken, fifteen, "Alexandrovichk 2"}
    assert Room.enter(room, "guest:c", sixteen) == {:taken, sixteen, "Alexandrovichk 2"}
  end

  test "the cut drops the space it would leave before the number" do
    room = enter!(room(), "guest:a", "Dana Kowalska Jo")

    assert Room.enter(room, "guest:b", "dana kowalska jo") ==
             {:taken, "Dana Kowalska Jo", "Dana Kowalska 2"}
  end

  test "a member who enters again keeps their Nickname and nothing changes" do
    room = enter!(room(), "guest:dana", "Dana")

    assert Room.enter(room, "guest:dana", "Someone else") == {:ok, room}
    assert Room.enter(room, "guest:dana", "dana") == {:ok, room}
    assert Room.enter(room, "guest:dana", "") == {:ok, room}
  end

  test "a Room takes 30 people and the 31st is full" do
    room = Enum.reduce(1..30, room(), &enter!(&2, "guest:#{&1}", "Person #{&1}"))

    assert Room.enter(room, "guest:31", "Person 31") == {:error, :full}
    assert Room.enter(room, "guest:1", "Person 1") == {:ok, room}
  end

  test "the view lists people in join order, marking the Host and the viewer" do
    room =
      room()
      |> enter!("guest:timur", "Timur")
      |> enter!(@host, "Malika")
      |> enter!("guest:dana", "Dana")

    assert Room.view_for(room, "guest:dana") == %{
             code: "KQXT",
             people: [
               %{
                 nickname: "Timur",
                 host?: false,
                 me?: false,
                 n: 1,
                 tally: 0,
                 sitting_out?: false,
                 playing?: false
               },
               %{
                 nickname: "Malika",
                 host?: true,
                 me?: false,
                 n: 2,
                 tally: 0,
                 sitting_out?: false,
                 playing?: false
               },
               %{
                 nickname: "Dana",
                 host?: false,
                 me?: true,
                 n: 3,
                 tally: 0,
                 sitting_out?: false,
                 playing?: false
               }
             ],
             me: "Dana",
             removed?: false,
             sitting_out?: false,
             playing?: false,
             host?: false,
             host_nickname: "Malika",
             can_start?: false,
             dealt_in: 3,
             game: nil,
             spectators: [],
             away: %{},
             host_away: nil,
             over: nil
           }

    assert %{me: "Malika", host?: true} = Room.view_for(room, @host)
  end

  test "the Host is not listed until they enter a Nickname, but knows they are the Host" do
    room = enter!(room(), "guest:dana", "Dana")

    assert %{people: [%{nickname: "Dana"}], me: nil, host?: true} = Room.view_for(room, @host)

    assert %{people: [%{nickname: "Dana"}], me: nil, host?: false} =
             Room.view_for(room, "guest:visitor")
  end

  test "the view never carries a person id, because a Guest id is that person's identity" do
    ids = [@host, "guest:dana", "guest:timur"]
    room = room() |> enter!(@host, "Malika") |> enter!("guest:dana", "Dana")

    for viewer <- ids, id <- ids do
      refute inspect(Room.view_for(room, viewer)) =~ id
    end
  end

  describe "starting a Game" do
    test "everyone in the Room is dealt in, in join order" do
      assert Room.dealt_in(lobby()) == ["guest:timur", @host, "guest:dana"]
    end

    test "the Host starts a Game with the seats as shuffled, everyone holding one die" do
      seats = ["guest:dana", "guest:timur", @host]

      {:ok, room} = Room.start_game(lobby(), @host, seats)

      assert room.game.seats == seats
      assert room.game.counts == %{"guest:dana" => 1, "guest:timur" => 1, @host => 1}
    end

    test "only the Host can start a Game" do
      assert Room.start_game(lobby(), "guest:dana", Room.dealt_in(lobby())) ==
               {:error, :not_host}
    end

    test "a Game needs two people" do
      room = enter!(room(), @host, "Malika")

      assert Room.start_game(room, @host, [@host]) == {:error, :too_few}
    end

    test "a Game cannot start while one is running" do
      {:ok, room} = Room.start_game(lobby(), @host, Room.dealt_in(lobby()))

      assert Room.start_game(room, @host, Room.dealt_in(room)) == {:error, :playing}
    end

    test "the seats must be exactly the people dealt in" do
      assert Room.start_game(lobby(), @host, ["guest:timur", @host]) == {:error, :wrong_seats}

      assert Room.start_game(lobby(), @host, ["guest:timur", @host, "guest:other"]) ==
               {:error, :wrong_seats}

      assert Room.start_game(lobby(), @host, ["guest:timur", @host, @host]) ==
               {:error, :wrong_seats}
    end
  end

  describe "sitting out" do
    defp sit_out!(room, person_id, sitting_out? \\ true) do
      {:ok, room} = Room.sit_out(room, person_id, sitting_out?)
      room
    end

    test "someone sitting out is not dealt in, and unticking deals them in again" do
      room = sit_out!(lobby(), @host)

      assert Room.dealt_in(room) == ["guest:timur", "guest:dana"]
      assert Room.dealt_in(sit_out!(room, @host, false)) == ["guest:timur", @host, "guest:dana"]
    end

    test "only a member can sit out" do
      assert Room.sit_out(lobby(), "guest:aziz", true) == {:error, :not_member}
    end

    test "the Game is dealt to the others only, and needs two of them" do
      room = sit_out!(lobby(), "guest:dana")

      assert Room.start_game(room, @host, [@host, "guest:dana", "guest:timur"]) ==
               {:error, :wrong_seats}

      {:ok, room} = Room.start_game(room, @host, [@host, "guest:timur"])
      assert room.game.seats == [@host, "guest:timur"]

      room = lobby() |> sit_out!("guest:timur") |> sit_out!(@host)
      assert Room.start_game(room, @host, ["guest:dana"]) == {:error, :too_few}
    end

    test "a Host sitting out still starts the Game for the others" do
      {:ok, room} =
        lobby() |> sit_out!(@host) |> Room.start_game(@host, ["guest:dana", "guest:timur"])

      assert room.game.seats == ["guest:dana", "guest:timur"]
    end

    test "a Player who ticks it mid-Game plays on, and sits out the Next Game" do
      room = sit_out!(playing(), "guest:dana")

      assert room.game.seats == ["guest:dana", "guest:timur", @host]

      assert %{seated?: true, my_dice: [6], my_turn?: true} =
               Room.view_for(room, "guest:dana").game

      assert {:ok, _room} = Room.raise(room, "guest:dana", 1, 6)
      assert Room.dealt_in(room) == ["guest:timur", @host]
    end
  end

  describe "the view of sitting out" do
    test "marks each person sitting out, and tells the viewer their own flag" do
      room = sit_out!(lobby(), "guest:dana")

      assert Enum.map(Room.view_for(room, "guest:timur").people, & &1.sitting_out?) ==
               [false, false, true]

      assert %{sitting_out?: true} = Room.view_for(room, "guest:dana")
      assert %{sitting_out?: false} = Room.view_for(room, "guest:timur")
      assert %{sitting_out?: false} = Room.view_for(room, "guest:aziz")
    end

    test "counts only those not sitting out as dealt in, and a start needs two of them" do
      room = sit_out!(lobby(), "guest:dana")
      assert %{dealt_in: 2, can_start?: true} = Room.view_for(room, @host)

      room = sit_out!(room, "guest:timur")
      assert %{dealt_in: 1, can_start?: false} = Room.view_for(room, @host)
    end
  end

  describe "the Spectators" do
    defp bek_sits_out, do: lobby() |> enter!("guest:bek", "Bek") |> sit_out!("guest:bek")

    defp spectators(room, viewer),
      do: for(s <- Room.view_for(room, viewer).spectators, do: {s.person.nickname, s.out?})

    test "are the Knocked out, those sitting out and late arrivals, in join order" do
      {:roll, room} = Room.next_round(dana_loses(%{"guest:dana" => 5}, [], bek_sits_out()), 1)

      room =
        room
        |> Room.start_round(%{"guest:timur" => [3], @host => [4]})
        |> enter!("guest:aziz", "Aziz")

      assert spectators(room, "guest:timur") == [{"Dana", true}, {"Bek", false}, {"Aziz", false}]

      assert %{nickname: "Aziz", me?: true, n: 5} =
               List.last(Room.view_for(room, "guest:aziz").spectators).person
    end

    test "take the one Knocked out from the Penalty die on, while their seat keeps its dice" do
      {:ok, room} = Room.reveal(dana_loses(%{"guest:dana" => 5}, [], bek_sits_out()), 1, 2)

      assert spectators(room, "guest:timur") == [{"Bek", false}]

      {:ok, room} = Room.reveal(room, 1, 3)

      assert spectators(room, "guest:timur") == [{"Dana", true}, {"Bek", false}]

      assert %{out?: false, dice: 6} =
               Enum.find(
                 Room.view_for(room, "guest:timur").game.seats,
                 &(&1.person.nickname == "Dana")
               )
    end

    test "are none with no Game on" do
      assert Room.view_for(bek_sits_out(), "guest:timur").spectators == []
    end

    test "carry no person id" do
      {:roll, room} = Room.next_round(dana_loses(%{"guest:dana" => 5}, [], bek_sits_out()), 1)
      ids = [@host, "guest:dana", "guest:timur", "guest:bek"]

      for viewer <- ids, id <- ids do
        refute inspect(Room.view_for(room, viewer)) =~ id
      end
    end
  end

  describe "playing" do
    test "with no Game running nobody can Raise or Check" do
      assert Room.raise(lobby(), @host, 1, 6) == {:error, :not_bidding}
      assert Room.check(lobby(), @host) == {:error, :not_bidding}
    end

    test "the first seat opens Round 1, and Raises and Checks go to the Game" do
      room = playing()
      assert room.game.round == 1

      assert Room.raise(room, "guest:timur", 1, 6) == {:error, :not_your_turn}
      {:ok, room} = Room.raise(room, "guest:dana", 1, 6)
      assert Room.check(room, "guest:dana") == {:error, :not_your_turn}
      {:ok, room} = Room.check(room, "guest:timur")

      assert %{loser: "guest:timur", step: 0} = room.game.reveal
    end

    test "a reveal step for the current Round's reveal moves it on; any other is stale" do
      {:ok, room} = Room.raise(playing(), "guest:dana", 3, 6)

      assert Room.reveal(room, 1, 1) == :stale
      assert Room.reveal(lobby(), 1, 1) == :stale

      {:ok, room} = Room.check(room, "guest:timur")

      assert Room.reveal(room, 2, 1) == :stale
      assert Room.reveal(room, 0, 1) == :stale

      assert {:ok, %{game: %{reveal: %{step: 3}, counts: %{"guest:dana" => 2}}}} =
               Room.reveal(room, 1, 3)
    end
  end

  defp dana_loses(counts, out \\ [], lobby \\ lobby()) do
    {:ok, room} = Room.start_game(lobby, @host, ["guest:dana", "guest:timur", @host])
    counts = Map.merge(%{"guest:dana" => 1, "guest:timur" => 1, @host => 1}, counts)
    room = %{room | game: %{room.game | counts: counts, out: out}}
    dice = for {id, n} <- counts, id not in out, into: %{}, do: {id, List.duplicate(1, n)}
    {:ok, room} = room |> Room.start_round(dice) |> Room.raise("guest:dana", 1, 6)
    {:ok, room} = Room.check(room, "guest:timur")
    room
  end

  describe "the next Round" do
    test "for another Round, or with no reveal running, is stale" do
      {:ok, raised} = Room.raise(playing(), "guest:dana", 3, 6)
      {:ok, checked} = Room.check(raised, "guest:timur")

      assert Room.next_round(lobby(), 1) == :stale
      assert Room.next_round(raised, 1) == :stale
      assert Room.next_round(checked, 2) == :stale
    end

    test "while two Players are left in play, rolls on, the Penalty die taken" do
      {:roll, room} = Room.next_round(dana_loses(%{"guest:dana" => 5}), 1)

      assert %{reveal: %{step: 3}, out: ["guest:dana"]} = room.game
      assert room.game.counts["guest:dana"] == 6
    end

    defp over do
      {:over, room} =
        %{"guest:dana" => 5, @host => 6}
        |> dana_loses([@host])
        |> Room.next_round(1)

      room
    end

    test "when one Player is left, ends the Game: the winner's Tally goes up, the Placement kept" do
      room = over()

      assert room.game == nil
      assert room.tally == %{"guest:timur" => 1}
      assert %{placement: ["guest:timur", "guest:dana", @host], rounds: 1} = room.last
      assert Room.next_round(room, 1) == :stale
    end

    test "after Game over the Host deals the Next Game, everyone back at one die, the Tally kept" do
      seats = [@host, "guest:dana", "guest:timur"]

      {:ok, room} = Room.start_game(over(), @host, seats)

      assert %{seats: ^seats, out: [], round: 0} = room.game
      assert room.game.counts == %{"guest:dana" => 1, "guest:timur" => 1, @host => 1}
      assert room.tally == %{"guest:timur" => 1}
      assert room.last == nil
    end
  end

  describe "a save" do
    defp second_game do
      {:ok, room} = Room.start_game(over(), @host, ["guest:dana", "guest:timur", @host])
      room = Room.start_round(room, %{"guest:dana" => [6], "guest:timur" => [2], @host => [4]})
      {:ok, room} = Room.raise(room, "guest:dana", 1, 6)
      room
    end

    test "holds no die faces, and keeps the members, Host, Tally, counts and Knock outs" do
      room = dana_loses(%{"guest:dana" => 5}) |> Room.reveal(1, 3) |> elem(1)

      saved = Room.to_save(room)

      assert saved.game.dice == %{}
      assert saved.game.bid == nil
      assert saved.game.reveal == nil

      assert Map.take(saved, [:code, :host_id, :members, :tally, :last]) ==
               Map.take(room, [:code, :host_id, :members, :tally, :last])

      assert %{counts: %{"guest:dana" => 6}, out: ["guest:dana"], round: 1} = saved.game
    end

    test "of a lobby restores as it is" do
      room = sit_out!(over(), "guest:timur")

      assert Room.restore(Room.to_save(room)) == {:ok, room}
    end

    test "mid-Game restores to be rolled again" do
      room = second_game()

      assert Room.restore(Room.to_save(room)) == {:roll, Room.to_save(room)}
    end

    test "taken after the Penalty die that ended the Game restores to the Game over" do
      {:ok, checked} =
        %{"guest:dana" => 5, @host => 6}
        |> dana_loses([@host])
        |> Room.reveal(1, 3)

      assert {:ok, room} = Room.restore(Room.to_save(checked))

      assert room == over()
      assert room.tally == %{"guest:timur" => 1}

      assert room.last == %{
               placement: ["guest:timur", "guest:dana", @host],
               rounds: 1,
               checks: [%{round: 1, checker: "guest:timur", bidder: "guest:dana", stood?: false}]
             }
    end

    test "from before a field existed restores with that field's default" do
      saved = Room.to_save(second_game())

      older = %{
        Map.delete(saved, :last)
        | members: Enum.map(saved.members, &Map.delete(&1, :sitting_out?)),
          game: Map.drop(saved.game, [:opener, :checks])
      }

      assert {:roll, room} = Room.restore(older)
      assert room.last == nil
      assert room.game.opener == nil
      assert room.game.checks == []
      assert Enum.all?(room.members, &(&1.sitting_out? == false))
      assert room.members |> Enum.map(& &1.nickname) == ["Timur", "Malika", "Dana"]
    end

    test "from before leaving existed restores every member as present" do
      saved = Room.to_save(second_game())
      older = %{saved | members: Enum.map(saved.members, &Map.drop(&1, [:left?, :removed?]))}

      assert {:roll, room} = Room.restore(older)
      assert Enum.all?(room.members, &(&1.left? == false and &1.removed? == false))
      assert Enum.all?(["guest:timur", @host, "guest:dana"], &Room.member?(room, &1))
    end

    test "of a Room everyone left restores with no Host, the next to enter taking the role" do
      room =
        Enum.reduce(["guest:timur", @host, "guest:dana"], lobby(), fn id, room ->
          {:ok, room} = Room.leave(room, id, [])
          room
        end)

      assert {:ok, restored} = Room.restore(Room.to_save(room))
      assert restored == room
      assert restored.host_id == nil

      assert {:ok, %{host_id: "guest:dana"}} = Room.enter(restored, "guest:dana", "Dana")
    end
  end

  test "a Check paces the reveal as the prototype does: 1.1 s, 2.7 s, 4.3 s, then 8.2 s" do
    {:ok, room} = Room.raise(playing(), "guest:dana", 1, 6)
    {:ok, room} = Room.check(room, "guest:timur")

    assert Room.reveal_schedule(room) == [
             {1100, {:reveal, 1, 1}},
             {2700, {:reveal, 1, 2}},
             {4300, {:reveal, 1, 3}},
             {8200, {:next_round, 1}}
           ]
  end

  describe "the lobby view" do
    test "names the Host and lets them start once two people are dealt in" do
      room = enter!(room(), @host, "Malika")

      assert %{host_nickname: "Malika", can_start?: false, dealt_in: 1, game: nil} =
               Room.view_for(room, @host)

      room = enter!(room, "guest:dana", "Dana")

      assert %{can_start?: true, dealt_in: 2} = Room.view_for(room, @host)
      assert %{host_nickname: "Malika", can_start?: false} = Room.view_for(room, "guest:dana")
    end

    test "has no Host Nickname while the Host has not entered one" do
      room = room() |> enter!("guest:dana", "Dana") |> enter!("guest:timur", "Timur")

      assert %{host_nickname: nil, dealt_in: 2} = Room.view_for(room, "guest:dana")
    end

    test "offers no start while a Game runs" do
      assert %{can_start?: false} = Room.view_for(playing(), @host)
    end
  end

  describe "the Game over view" do
    test "gives every person their Tally, nothing won being 0" do
      assert Enum.map(Room.view_for(over(), "guest:dana").people, &{&1.nickname, &1.tally}) ==
               [{"Timur", 1}, {"Malika", 0}, {"Dana", 0}]
    end

    test "shows the winner and the Placement after how many Rounds, the viewer marked" do
      timur = %{nickname: "Timur", me?: false, n: 1}
      malika = %{nickname: "Malika", me?: false, n: 2}
      dana = %{nickname: "Dana", me?: true, n: 3}

      assert Room.view_for(over(), "guest:dana").over == %{
               winner: timur,
               placement: [timur, dana, malika],
               rounds: 1
             }

      assert %{winner: %{nickname: "Timur", me?: true}} =
               Room.view_for(over(), "guest:timur").over
    end

    test "is there only between a Game over and the Next Game" do
      {:ok, next} = Room.start_game(over(), @host, Room.dealt_in(lobby()))

      for room <- [lobby(), playing(), next] do
        assert Room.view_for(room, "guest:dana").over == nil
      end
    end

    test "offers the Host the Next Game" do
      assert %{can_start?: true, game: nil} = Room.view_for(over(), @host)
      assert %{can_start?: false} = Room.view_for(over(), "guest:dana")
    end

    test "carries no person id" do
      ids = [@host, "guest:dana", "guest:timur"]

      for viewer <- ids, id <- ids do
        refute inspect(Room.view_for(over(), viewer)) =~ id
      end
    end
  end

  describe "the game view with a Player Knocked out" do
    defp dana_knocked_out, do: dana_loses(%{"guest:dana" => 5}) |> Room.reveal(1, 3) |> elem(1)

    defp next_round_after_dana do
      {:roll, room} = Room.next_round(dana_loses(%{"guest:dana" => 5}), 1)
      Room.start_round(room, %{"guest:timur" => [3], @host => [4]})
    end

    defp out_seats(room, viewer),
      do:
        for(seat <- Room.view_for(room, viewer).game.seats, do: {seat.person.nickname, seat.out?})

    test "marks the seat out from the Round after the Knock out, not during its reveal" do
      assert out_seats(dana_knocked_out(), "guest:timur") ==
               [{"Timur", false}, {"Malika", false}, {"Dana", false}]

      assert out_seats(next_round_after_dana(), "guest:timur") ==
               [{"Timur", false}, {"Malika", false}, {"Dana", true}]
    end

    test "a Knocked-out Player watches from the next Round: no dice of their own, no faces" do
      view = Room.view_for(next_round_after_dana(), "guest:dana").game

      assert %{seated?: false, knocked_out?: true, my_dice: nil, my_turn?: false} = view
      assert %{can_check?: false} = view
      assert Enum.map(view.seats, & &1.faces) == [nil, nil, nil]
      assert Enum.map(view.seats, & &1.person.nickname) == ["Dana", "Timur", "Malika"]
    end

    test "the one Knocked out still plays out the reveal from their seat" do
      assert %{seated?: true, knocked_out?: false, my_dice: [1, 1, 1, 1, 1]} =
               Room.view_for(dana_knocked_out(), "guest:dana").game
    end

    test "the reveal says the Penalty die Knocked the loser out, from step 3" do
      {:ok, at_two} = Room.reveal(dana_loses(%{"guest:dana" => 5}), 1, 2)
      {:ok, ordinary} = Room.reveal(dana_loses(%{"guest:dana" => 4}), 1, 3)

      assert %{knocked_out?: false, loser: nil} =
               Room.view_for(at_two, "guest:timur").game.reveal

      assert %{knocked_out?: true, loser: %{nickname: "Dana"}} =
               Room.view_for(dana_knocked_out(), "guest:timur").game.reveal

      assert %{knocked_out?: false, loser: %{nickname: "Dana"}} =
               Room.view_for(ordinary, "guest:timur").game.reveal
    end

    test "carries no person id" do
      ids = [@host, "guest:dana", "guest:timur"]

      for room <- [dana_knocked_out(), next_round_after_dana()], viewer <- ids, id <- ids do
        refute inspect(Room.view_for(room, viewer)) =~ id
      end
    end

    test "nobody else is Knocked out" do
      for viewer <- ["guest:timur", @host, "guest:aziz"] do
        room = enter!(next_round_after_dana(), "guest:aziz", "Aziz")
        assert %{knocked_out?: false} = Room.view_for(room, viewer).game
      end
    end
  end

  describe "the game view" do
    @timur %{nickname: "Timur", me?: true, n: 1}
    @malika %{nickname: "Malika", me?: false, n: 2}
    @dana %{nickname: "Dana", me?: false, n: 3}

    defp raised do
      {:ok, room} = Room.raise(playing(), "guest:dana", 1, 6)
      room
    end

    test "shows a seated Player their own dice, the Bid, and the seats from theirs, clockwise" do
      assert Room.view_for(raised(), "guest:timur").game == %{
               round: 1,
               dice_on_table: 3,
               seated?: true,
               knocked_out?: false,
               my_dice: [2],
               my_turn?: true,
               can_check?: true,
               turn: @timur,
               bid: %{count: 1, face: 6, by: @dana},
               seats: [
                 %{
                   person: @timur,
                   dice: 1,
                   said: nil,
                   on_turn?: true,
                   faces: nil,
                   penalty?: false,
                   out?: false
                 },
                 %{
                   person: @malika,
                   dice: 1,
                   said: nil,
                   on_turn?: false,
                   faces: nil,
                   penalty?: false,
                   out?: false
                 },
                 %{
                   person: @dana,
                   dice: 1,
                   said: %{count: 1, face: 6},
                   on_turn?: false,
                   faces: nil,
                   penalty?: false,
                   out?: false
                 }
               ],
               reveal: nil,
               voided_by: nil
             }
    end

    defp checked do
      {:ok, room} = Room.check(raised(), "guest:timur")
      room
    end

    defp at_step(step) do
      {:ok, room} = Room.reveal(checked(), 1, step)
      room
    end

    defp faces(view), do: Enum.map(view.game.seats, & &1.faces)

    test "before reveal step 1 nobody's faces are on the table, and you hold only your own" do
      for room <- [playing(), raised(), checked()] do
        assert %{my_dice: [2]} = Room.view_for(room, "guest:timur").game
        assert %{my_dice: [6]} = Room.view_for(room, "guest:dana").game
        assert faces(Room.view_for(room, "guest:timur")) == [nil, nil, nil]
      end
    end

    test "someone not seated sees the table from the first seat, with no faces" do
      room = enter!(raised(), "guest:aziz", "Aziz")
      view = Room.view_for(room, "guest:aziz")

      assert %{seated?: false, my_dice: nil, my_turn?: false, can_check?: false} = view.game
      assert faces(view) == [nil, nil, nil]
      assert Enum.map(view.game.seats, & &1.person.nickname) == ["Dana", "Timur", "Malika"]
      assert view.dealt_in == 4
    end

    test "Check is not on offer to the opener, to a Player off turn, or during the reveal" do
      assert %{my_turn?: true, can_check?: false} = Room.view_for(playing(), "guest:dana").game
      assert %{my_turn?: false, can_check?: false} = Room.view_for(raised(), @host).game

      assert %{my_turn?: false, can_check?: false, turn: nil} =
               Room.view_for(checked(), "guest:timur").game
    end

    test "at reveal step 0 the Check and the Bid show, with no count, verdict or loser" do
      assert Room.view_for(checked(), "guest:timur").game.reveal == %{
               step: 0,
               checker: @timur,
               bid: %{count: 1, face: 6, by: @dana},
               count: nil,
               stood?: nil,
               loser: nil,
               knocked_out?: false
             }
    end

    test "at reveal step 1 every seat's faces turn over, the count still hidden" do
      view = Room.view_for(at_step(1), "guest:aziz")

      assert faces(view) == [[6], [2], [6]]
      assert %{count: nil, stood?: nil, loser: nil} = view.game.reveal
      assert faces(Room.view_for(at_step(1), "guest:timur")) == [[2], [6], [6]]
    end

    test "at reveal step 2 the count and the verdict land, the loser still hidden" do
      assert %{count: 2, stood?: true, loser: nil} =
               Room.view_for(at_step(2), "guest:timur").game.reveal
    end

    test "at reveal step 3 the loser takes the Penalty die" do
      game = Room.view_for(at_step(3), "guest:timur").game

      assert game == %{
               round: 1,
               dice_on_table: 4,
               seated?: true,
               knocked_out?: false,
               my_dice: [2],
               my_turn?: false,
               can_check?: false,
               turn: nil,
               bid: %{count: 1, face: 6, by: @dana},
               seats: [
                 %{
                   person: @timur,
                   dice: 2,
                   said: nil,
                   on_turn?: false,
                   faces: [2],
                   penalty?: true,
                   out?: false
                 },
                 %{
                   person: @malika,
                   dice: 1,
                   said: nil,
                   on_turn?: false,
                   faces: [6],
                   penalty?: false,
                   out?: false
                 },
                 %{
                   person: @dana,
                   dice: 1,
                   said: %{count: 1, face: 6},
                   on_turn?: false,
                   faces: [6],
                   penalty?: false,
                   out?: false
                 }
               ],
               reveal: %{
                 step: 3,
                 checker: @timur,
                 bid: %{count: 1, face: 6, by: @dana},
                 count: 2,
                 stood?: true,
                 loser: @timur,
                 knocked_out?: false
               },
               voided_by: nil
             }
    end

    test "carries no person id, at any point in the Round" do
      ids = [@host, "guest:dana", "guest:timur", "guest:aziz"]

      for room <- [playing(), raised(), checked(), at_step(1), at_step(3)],
          room = enter!(room, "guest:aziz", "Aziz"),
          viewer <- ids,
          id <- ids do
        refute inspect(Room.view_for(room, viewer)) =~ id
      end
    end
  end

  describe "leaving" do
    test "in the lobby takes the person out of the Room, the others keeping their numbers" do
      assert {:ok, room} = Room.leave(lobby(), "guest:timur", [])

      refute Room.member?(room, "guest:timur")
      assert Room.dealt_in(room) == [@host, "guest:dana"]

      assert [%{nickname: "Malika", n: 2}, %{nickname: "Dana", n: 3, me?: true}] =
               Room.view_for(room, "guest:dana").people

      assert %{me: nil} = Room.view_for(room, "guest:timur")
    end

    test "mid-Round Knocks the Player out and voids the Round, for the Room to roll again" do
      assert {:roll, room} = Room.leave(playing(), "guest:dana", [])

      refute Room.member?(room, "guest:dana")
      assert %{out: ["guest:dana"], voided_by: "guest:dana", dice: %{}, turn: nil} = room.game

      room = Room.start_round(room, %{"guest:timur" => [3], @host => [4]})

      assert %{round: 2, turn: "guest:timur"} = room.game
    end

    test "by one of the last two Players ends the Game: the other wins, the Tally goes up" do
      room = dana_loses(%{@host => 6}, [@host])

      assert {:ok, room} = Room.leave(room, "guest:timur", [])

      assert room.game == nil
      assert room.tally == %{"guest:dana" => 1}
      assert %{placement: ["guest:dana", "guest:timur", @host], rounds: 1} = room.last

      assert %{winner: %{nickname: "Dana"}, placement: [_, %{nickname: "Timur"}, _]} =
               Room.view_for(room, "guest:dana").over
    end

    test "by a Spectator mid-Game leaves the Game as it is" do
      room = enter!(playing(), "guest:aziz", "Aziz")

      assert {:ok, left} = Room.leave(room, "guest:aziz", [])
      assert left.game == room.game
    end

    test "is refused to someone not in the Room, and to someone who already left" do
      {:ok, room} = Room.leave(lobby(), "guest:timur", [])

      assert Room.leave(room, "guest:timur", []) == {:error, :not_member}
      assert Room.leave(room, "guest:aziz", []) == {:error, :not_member}
    end
  end

  describe "the Host leaving" do
    test "passes the role to the first connected person still in the Room" do
      {:ok, room} = Room.leave(lobby(), "guest:timur", [])
      connected = [@host, "guest:visitor", "guest:timur", "guest:dana"]

      assert {:ok, room} = Room.leave(room, @host, connected)

      assert room.host_id == "guest:dana"
      assert %{host?: true, host_nickname: "Dana"} = Room.view_for(room, "guest:dana")
    end

    test "with nobody in the Room connected, passes it to whoever entered first" do
      room = enter!(lobby(), "guest:aziz", "Aziz")

      assert {:ok, %{host_id: "guest:timur"}} = Room.leave(room, @host, [@host, "guest:visitor"])

      {:ok, room} = Room.leave(room, "guest:timur", [])

      assert {:ok, %{host_id: "guest:dana"}} = Room.leave(room, @host, ["guest:timur"])
    end

    test "last leaves the Room with no Host, and the next to enter becomes Host" do
      room = enter!(room(), @host, "Malika")

      assert {:ok, room} = Room.leave(room, @host, [@host])
      assert room.host_id == nil
      assert %{host?: false, host_nickname: nil, people: []} = Room.view_for(room, "guest:dana")

      room = enter!(room, "guest:dana", "Dana")

      assert room.host_id == "guest:dana"
      assert %{host?: true, host_nickname: "Dana"} = Room.view_for(room, "guest:dana")
    end
  end

  describe "coming back after leaving" do
    test "in the lobby, a person is back with their own number and the Nickname they enter" do
      {:ok, room} = lobby() |> sit_out!("guest:timur") |> Room.leave("guest:timur", [])

      room = enter!(room, "guest:timur", "  Timka ")

      assert Room.member?(room, "guest:timur")
      assert Room.dealt_in(room) == ["guest:timur", @host, "guest:dana"]

      assert [%{nickname: "Timka", n: 1, me?: true, sitting_out?: false}, _, _] =
               Room.view_for(room, "guest:timur").people
    end

    test "mid-Game, a Player who left is back as a Spectator, Knocked out, seat and number kept" do
      {:roll, room} = Room.leave(playing(), "guest:dana", [])
      room = Room.start_round(room, %{"guest:timur" => [3], @host => [4]})

      assert spectators(room, "guest:timur") == []

      room = enter!(room, "guest:dana", "Dana")

      assert spectators(room, "guest:timur") == [{"Dana", true}]
      view = Room.view_for(room, "guest:dana")
      assert %{seated?: false, knocked_out?: true, my_dice: nil} = view.game
      assert [%{person: %{nickname: "Dana", me?: true, n: 3}, out?: true} | _] = view.game.seats
    end

    test "while someone is gone their Nickname is free, and taken when they come back" do
      {:ok, room} = Room.leave(lobby(), "guest:dana", [])
      room = enter!(room, "guest:aziz", "dana")

      assert Room.enter(room, "guest:dana", "Dana") == {:taken, "dana", "dana 2"}
    end

    test "mid-Game, the Nickname of a Player who left is held while their seat is at the table" do
      {:roll, room} = Room.leave(playing(), "guest:dana", [])

      assert Room.enter(room, "guest:aziz", "dana") == {:taken, "Dana", "Dana 2"}
      assert {:ok, _room} = Room.enter(room, "guest:dana", "Dana")
    end

    test "a Room is full at 30 present, not counting those who left" do
      room = Enum.reduce(1..30, room(), &enter!(&2, "guest:#{&1}", "Person #{&1}"))
      {:ok, room} = Room.leave(room, "guest:1", [])

      room = enter!(room, "guest:31", "Person 31")

      assert Room.enter(room, "guest:1", "Person 1") == {:error, :full}
    end
  end

  describe "the Host removing someone" do
    test "mid-Round names them by number, Knocks them out and voids the Round" do
      assert {:roll, room} = Room.remove(playing(), @host, 3, [])

      refute Room.member?(room, "guest:dana")
      assert %{out: ["guest:dana"], voided_by: "guest:dana"} = room.game
    end

    test "tells the removed person so until they enter again, and nobody who left or never came" do
      {:roll, room} = Room.remove(playing(), @host, 3, [])
      {:ok, room} = Room.leave(room, "guest:timur", [])

      assert %{removed?: true, me: nil} = Room.view_for(room, "guest:dana")
      assert %{removed?: false} = Room.view_for(room, "guest:timur")
      assert %{removed?: false} = Room.view_for(room, "guest:aziz")
      assert %{removed?: false} = Room.view_for(room, @host)

      assert %{removed?: false, me: "Dana"} =
               Room.view_for(enter!(room, "guest:dana", "Dana"), "guest:dana")
    end

    test "is the Host's alone, of someone present other than the Host" do
      {:ok, room} = Room.leave(lobby(), "guest:timur", [])

      assert Room.remove(room, "guest:dana", 2, []) == {:error, :not_host}
      assert Room.remove(room, @host, 1, []) == {:error, :not_member}
      assert Room.remove(room, @host, 4, []) == {:error, :not_member}
      assert Room.remove(room, @host, 0, []) == {:error, :not_member}
      assert Room.remove(room, @host, 2, []) == {:error, :self}
    end
  end

  describe "handing over the Host role" do
    test "makes the person with that number the Host, the old Host a person like any other" do
      assert {:ok, room} = Room.make_host(playing(), @host, 1)

      assert room.host_id == "guest:timur"
      assert %{host?: true, host_nickname: "Timur"} = Room.view_for(room, "guest:timur")
      assert %{host?: false} = Room.view_for(room, @host)
      assert Room.make_host(room, @host, 3) == {:error, :not_host}
    end

    test "is the Host's alone, to someone present other than the Host" do
      {:ok, room} = Room.leave(lobby(), "guest:timur", [])

      assert Room.make_host(room, "guest:dana", 3) == {:error, :not_host}
      assert Room.make_host(room, @host, 1) == {:error, :not_member}
      assert Room.make_host(room, @host, 9) == {:error, :not_member}
      assert Room.make_host(room, @host, 2) == {:error, :self}
    end
  end

  describe "the view of who is playing" do
    defp playing_flags(room, viewer),
      do: for(p <- Room.view_for(room, viewer).people, do: {p.nickname, p.playing?})

    test "marks the Players in play, and tells the viewer whether they are one" do
      room = next_round_after_dana() |> enter!("guest:aziz", "Aziz")

      assert playing_flags(room, "guest:aziz") ==
               [{"Timur", true}, {"Malika", true}, {"Dana", false}, {"Aziz", false}]

      assert %{playing?: true} = Room.view_for(room, "guest:timur")
      assert %{playing?: false} = Room.view_for(room, "guest:dana")
      assert %{playing?: false} = Room.view_for(room, "guest:aziz")
    end

    test "marks nobody with no Game on" do
      assert playing_flags(over(), @host) == [
               {"Timur", false},
               {"Malika", false},
               {"Dana", false}
             ]

      assert %{playing?: false} = Room.view_for(lobby(), @host)
    end
  end

  describe "Away" do
    defp away(room, viewer), do: Room.view_for(room, viewer).away

    test "a member who goes Away shows by number, with since when, to everyone but themselves" do
      room = Room.away(lobby(), "guest:dana", 1_000)

      assert away(room, @host) == %{3 => 1_000}
      assert away(room, "guest:timur") == %{3 => 1_000}
      assert away(room, "guest:dana") == %{}
      assert away(lobby(), @host) == %{}
    end

    test "going Away again keeps the first since, and coming back clears it" do
      room = lobby() |> Room.away("guest:dana", 1_000) |> Room.away("guest:dana", 5_000)

      assert away(room, @host) == %{3 => 1_000}
      assert away(Room.back(room, "guest:dana"), @host) == %{}
    end

    test "only a member goes Away: someone who never entered, or who left, changes nothing" do
      {:ok, left} = Room.leave(lobby(), "guest:timur", [])

      assert Room.away(lobby(), "guest:aziz", 1_000) == lobby()
      assert Room.away(left, "guest:timur", 1_000) == left
    end

    test "leaving or being removed ends being Away, so a person who enters again is not Away" do
      room = Room.away(lobby(), "guest:dana", 1_000)
      {:ok, left} = Room.leave(room, "guest:dana", [])
      {:ok, removed} = Room.remove(room, @host, 3, [])

      for room <- [left, removed] do
        assert away(enter!(room, "guest:dana", "Dana"), @host) == %{}
      end
    end

    test "an Away person is not dealt in, and watches as a Spectator once back" do
      room = Room.away(lobby(), "guest:dana", 1_000)

      assert Room.dealt_in(room) == ["guest:timur", @host]
      assert %{dealt_in: 2, can_start?: true} = Room.view_for(room, @host)

      assert Room.start_game(room, @host, ["guest:timur", @host, "guest:dana"]) ==
               {:error, :wrong_seats}

      {:ok, room} = Room.start_game(room, @host, ["guest:timur", @host])
      room = Room.back(room, "guest:dana")

      assert %{game: %{seated?: false}, spectators: [%{person: %{me?: true}, out?: false}]} =
               Room.view_for(room, "guest:dana")
    end

    test "with one of two people Away, the Host cannot start a Game" do
      room =
        room()
        |> enter!(@host, "Malika")
        |> enter!("guest:dana", "Dana")
        |> Room.away("guest:dana", 1_000)

      assert %{dealt_in: 1, can_start?: false} = Room.view_for(room, @host)
      assert Room.start_game(room, @host, [@host]) == {:error, :too_few}
    end

    test "an Away Player not on turn: their dice count in a Check and they take the Penalty die" do
      {:ok, room} = Room.raise(playing(), "guest:dana", 1, 6)
      {:ok, room} = Room.raise(room, "guest:timur", 2, 6)
      {:ok, room} = Room.raise(room, @host, 3, 6)
      room = Room.away(room, @host, 1_000)

      {:ok, room} = Room.check(room, "guest:dana")
      {:ok, room} = Room.reveal(room, 1, 3)

      assert %{count: 2, stood?: false, loser: %{nickname: "Malika"}} =
               Room.view_for(room, "guest:dana").game.reveal

      assert room.game.counts[@host] == 2
    end
  end

  describe "the Host Away" do
    defp no_shuffle(_connected), do: flunk("shuffled with no handover")

    defp host_away(room \\ lobby(), at \\ 1_000),
      do: room |> Room.away(@host, at) |> Room.settle_handover(at, &no_shuffle/1)

    test "starts the handover: the role passes on 2 minutes after the Host went Away" do
      room = host_away()

      assert room.handover == %{host: @host, ends_at: 121_000, vote: nil, vote_again_at: nil}
      assert Room.settle_handover(room, 120_999, &no_shuffle/1).host_id == @host
      assert Room.settle_handover(room, 121_000, &Enum.reverse/1).host_id == "guest:dana"
    end

    test "settling again keeps the handover running from when it started" do
      room = Room.settle_handover(host_away(), 50_000, &no_shuffle/1)

      assert room.handover.ends_at == 121_000
    end

    test "is nothing while the Host is connected, or with no Host" do
      assert Room.settle_handover(lobby(), 1_000, &no_shuffle/1).handover == nil

      {:ok, hostless} = Room.leave(enter!(room(), @host, "Malika"), @host, [])
      assert Room.settle_handover(hostless, 1_000, &no_shuffle/1).handover == nil
    end

    test "the Host coming back cancels it and any vote, and they stay Host" do
      {:ok, room} = Room.start_vote(host_away(), "guest:dana", 2_000)

      room = room |> Room.back(@host) |> Room.settle_handover(200_000, &no_shuffle/1)

      assert room.handover == nil
      assert room.host_id == @host
    end

    test "a new Host who is Away gets their own fresh 2 minutes" do
      room = lobby() |> Room.away("guest:dana", 1_000) |> host_away(2_000)
      {:ok, room} = Room.make_host(room, @host, 3)

      room = Room.settle_handover(room, 50_000, &no_shuffle/1)

      assert room.handover == %{
               host: "guest:dana",
               ends_at: 170_000,
               vote: nil,
               vote_again_at: nil
             }
    end

    test "when the 2 minutes run out, the role goes to someone connected, in the order shuffled" do
      room =
        lobby() |> enter!("guest:aziz", "Aziz") |> host_away() |> Room.away("guest:dana", 5_000)

      assert %{host_id: "guest:timur", handover: nil} = Room.settle_handover(room, 121_000, & &1)
      assert %{host_id: "guest:aziz"} = Room.settle_handover(room, 121_000, &Enum.reverse/1)
    end

    test "with nobody connected the role stays, and goes to the first person back" do
      room = host_away() |> Room.away("guest:dana", 1_000) |> Room.away("guest:timur", 1_000)

      room = Room.settle_handover(room, 121_000, & &1)

      assert room.host_id == @host
      assert room.handover.ends_at == 121_000

      room = room |> Room.back("guest:timur") |> Room.settle_handover(130_000, & &1)

      assert room.host_id == "guest:timur"
      assert room.handover == nil
    end

    test "the timer's handover passes the role before the deadline, to someone connected" do
      room = Room.away(host_away(), "guest:dana", 5_000)
      nobody = Room.away(room, "guest:timur", 5_000)

      assert %{host_id: "guest:timur", handover: nil} = Room.hand_over(room, & &1)
      assert Room.hand_over(nobody, & &1) == nobody
      assert Room.hand_over(lobby(), &no_shuffle/1) == lobby()
    end
  end

  describe "the vote to pass the Host role" do
    defp voting(room \\ lobby()) do
      {:ok, room} = room |> host_away() |> Room.start_vote("guest:dana", 5_000)
      room
    end

    defp vote!(room, by, yes? \\ true, at \\ 6_000) do
      {:ok, room} = Room.vote(room, by, yes?, at)
      room
    end

    defp settle(room), do: Room.settle_handover(room, 7_000, & &1)

    test "passes once every connected person said yes, a Spectator included, the starter counted" do
      room = playing() |> enter!("guest:aziz", "Aziz") |> voting() |> vote!("guest:timur")

      assert settle(room).host_id == @host

      passed = room |> vote!("guest:aziz") |> settle()

      assert passed.host_id == "guest:timur"
      assert passed.handover == nil
    end

    test "an Away person is neither needed nor counted, so a lone connected starter passes it" do
      room = voting() |> Room.away("guest:timur", 5_500)

      assert settle(room).host_id == "guest:dana"
    end

    test "with nobody connected it never passes" do
      room = voting() |> Room.away("guest:dana", 5_500) |> Room.away("guest:timur", 5_500)

      assert settle(room).host_id == @host
    end

    test "a yes from someone already in, or a second yes, changes nothing" do
      room = vote!(voting(), "guest:timur")

      assert Room.vote(room, "guest:timur", true, 6_500) == {:ok, room}
      assert Room.vote(room, "guest:dana", true, 6_500) == {:ok, room}
    end

    test "fails on the first no, and a new vote cannot start for 30 seconds" do
      room = vote!(voting(), "guest:timur", false, 10_000)

      assert room.handover.vote == nil
      assert room.handover.vote_again_at == 40_000
      assert settle(room).host_id == @host
      assert Room.start_vote(room, "guest:timur", 39_999) == {:error, :too_soon}

      assert {:ok, %{handover: %{vote: %{by: "guest:timur"}}}} =
               Room.start_vote(room, "guest:timur", 40_000)
    end

    test "fails when its 30 seconds run out, the same as a no" do
      assert voting().handover.vote.ends_at == 35_000

      room = Room.vote_over(voting(), 35_000)

      assert room.handover.vote == nil
      assert room.handover.vote_again_at == 65_000
      assert Room.vote_over(room, 70_000) == room
    end

    test "ended late, as after a restore, still waits from its deadline, not from when it ended" do
      room = Room.vote_over(voting(), 50_000)

      assert room.handover.vote_again_at == 65_000
    end

    test "starts only while the Host is Away, from someone connected, with no vote open" do
      {:ok, left} = Room.leave(host_away(), "guest:timur", [])
      room = Room.away(host_away(), "guest:timur", 2_000)

      assert Room.start_vote(lobby(), "guest:dana", 5_000) == {:error, :no_handover}
      assert Room.start_vote(room, "guest:timur", 5_000) == {:error, :not_member}
      assert Room.start_vote(room, "guest:aziz", 5_000) == {:error, :not_member}
      assert Room.start_vote(left, "guest:timur", 5_000) == {:error, :not_member}
      assert Room.start_vote(voting(), "guest:timur", 5_000) == {:error, :voting}
    end

    test "a vote is taken only while one is open, from someone connected" do
      room = Room.away(voting(), "guest:timur", 5_500)

      assert Room.vote(host_away(), "guest:dana", true, 6_000) == {:error, :no_vote}
      assert Room.vote(room, "guest:timur", true, 6_000) == {:error, :not_member}
      assert Room.vote(room, "guest:timur", false, 6_000) == {:error, :not_member}
      assert Room.vote(room, "guest:aziz", false, 6_000) == {:error, :not_member}
    end
  end

  describe "the view of the Host Away" do
    defp host_away_view(room, viewer), do: Room.view_for(room, viewer).host_away

    test "shows everyone but the Host since when, and when the role passes on" do
      room = host_away()

      for viewer <- ["guest:timur", "guest:dana", "guest:aziz"] do
        assert host_away_view(room, viewer) ==
                 %{since: 1_000, ends_at: 121_000, vote: nil, vote_again_at: nil}
      end

      assert host_away_view(room, @host) == nil
      assert host_away_view(lobby(), "guest:dana") == nil
    end

    test "during a vote, shows who asked, how many of those connected said yes, and the time left" do
      room = playing() |> enter!("guest:aziz", "Aziz") |> voting() |> vote!("guest:aziz")

      assert host_away_view(room, "guest:timur") == %{
               since: 1_000,
               ends_at: 121_000,
               vote: %{
                 by: %{nickname: "Dana", me?: false, n: 3},
                 yes: 2,
                 of: 3,
                 ends_at: 35_000,
                 said_yes?: false
               },
               vote_again_at: nil
             }

      assert %{by: %{me?: true}, said_yes?: true} = host_away_view(room, "guest:dana").vote
      assert %{yes: 2, of: 3, said_yes?: true} = host_away_view(room, "guest:aziz").vote
      assert host_away_view(room, @host) == nil
    end

    test "counts neither yes nor voter for someone who went Away or left" do
      {:ok, room} = voting() |> vote!("guest:timur") |> Room.leave("guest:timur", [])

      assert %{yes: 1, of: 1} = host_away_view(room, "guest:dana").vote

      room = voting() |> vote!("guest:timur") |> Room.away("guest:timur", 6_500)

      assert %{yes: 1, of: 1} = host_away_view(room, "guest:dana").vote
    end

    test "after a failed vote, says when a new one may start" do
      room = vote!(voting(), "guest:timur", false, 10_000)

      assert %{vote: nil, vote_again_at: 40_000} = host_away_view(room, "guest:timur")
    end

    test "carries no person id" do
      room = playing() |> enter!("guest:aziz", "Aziz") |> voting() |> vote!("guest:aziz")
      ids = [@host, "guest:dana", "guest:timur", "guest:aziz"]

      for viewer <- ids, id <- ids do
        refute inspect(Room.view_for(room, viewer)) =~ id
      end
    end
  end

  describe "a save of the Host Away" do
    test "keeps the handover and its vote, deadlines and all" do
      room = vote!(voting(), "guest:timur")

      assert Room.restore(Room.to_save(room)) == {:ok, room}
    end

    test "from before the handover existed restores with none" do
      older = Map.delete(Room.to_save(lobby()), :handover)

      assert {:ok, %{handover: nil}} = Room.restore(older)
    end
  end

  describe "the view of a voided Round" do
    defp dana_left do
      {:roll, room} = Room.leave(playing(), "guest:dana", [@host])
      Room.start_round(room, %{"guest:timur" => [3], @host => [4]})
    end

    test "names who left on the re-rolled Round, and nobody otherwise" do
      assert %{voided_by: %{nickname: "Dana", me?: false, n: 3}, turn: %{nickname: "Timur"}} =
               Room.view_for(dana_left(), "guest:timur").game

      assert %{voided_by: nil} = Room.view_for(playing(), "guest:timur").game
    end

    test "carries no person id, the one who left included" do
      ids = [@host, "guest:dana", "guest:timur"]
      {:ok, handed} = Room.make_host(dana_left(), @host, 1)

      for room <- [dana_left(), handed], viewer <- ids, id <- ids do
        refute inspect(Room.view_for(room, viewer)) =~ id
      end
    end
  end

  describe "what finished" do
    test "is nothing mid-Game, at the Game's start, or between Games" do
      {:ok, raised} = Room.raise(playing(), "guest:dana", 3, 6)
      {:ok, checked} = Room.check(raised, "guest:timur")
      {:ok, settled} = Room.reveal(checked, 1, 3)
      {:roll, rolled} = Room.next_round(dana_loses(%{"guest:dana" => 5}), 1)
      {:ok, next_game} = Room.start_game(over(), @host, [@host, "guest:dana", "guest:timur"])

      assert Room.finished(lobby(), playing()) == nil
      assert Room.finished(raised, checked) == nil
      assert Room.finished(checked, settled) == nil
      assert Room.finished(dana_loses(%{"guest:dana" => 5}), rolled) == nil
      assert Room.finished(over(), enter!(over(), "guest:aziz", "Aziz")) == nil
      assert Room.finished(over(), next_game) == nil
    end

    test "after the last Penalty die is the Game with every Placement, Nickname and Check" do
      before = dana_loses(%{"guest:dana" => 5, @host => 6}, [@host])
      {:over, room} = Room.next_round(before, 1)

      assert Room.finished(before, room) == %{
               room_code: "KQXT",
               rounds: 1,
               placement: [
                 %{person_id: "guest:timur", nickname: "Timur", place: 1},
                 %{person_id: "guest:dana", nickname: "Dana", place: 2},
                 %{person_id: @host, nickname: "Malika", place: 3}
               ],
               checks: [%{round: 1, checker: "guest:timur", bidder: "guest:dana", stood?: false}]
             }
    end

    test "after a leave in the reveal that ends the Game keeps the leaver's Nickname, place and every Check" do
      {:roll, room} = Room.next_round(dana_loses(%{}, [@host]), 1)

      {:ok, before} =
        room
        |> Room.start_round(%{"guest:dana" => [2, 2], "guest:timur" => [3]})
        |> Room.raise("guest:dana", 1, 2)

      {:ok, before} = Room.check(before, "guest:timur")
      {:ok, room} = Room.leave(before, "guest:timur", [])

      assert %{
               rounds: 2,
               placement: [
                 %{person_id: "guest:dana", nickname: "Dana", place: 1},
                 %{person_id: "guest:timur", nickname: "Timur", place: 2},
                 %{person_id: @host, nickname: "Malika", place: 3}
               ],
               checks: [
                 %{round: 1, checker: "guest:timur", bidder: "guest:dana", stood?: false},
                 %{round: 2, checker: "guest:timur", bidder: "guest:dana", stood?: true}
               ]
             } = Room.finished(before, room)
    end
  end

  describe "moving a Guest's seat to their Account" do
    @account "account:1"

    defp people(room, viewer),
      do: for(p <- Room.view_for(room, viewer).people, do: {p.n, p.nickname, p.host?, p.me?})

    test "of a Guest not in the Room, or who left it, changes nothing" do
      {:ok, left} = Room.leave(lobby(), "guest:timur", [])

      assert Room.move_seat(lobby(), "guest:aziz", @account) == {:ok, lobby()}
      assert Room.move_seat(left, "guest:timur", @account) == {:ok, left}
    end

    test "onto the same person changes nothing" do
      assert Room.move_seat(lobby(), "guest:dana", "guest:dana") == {:ok, lobby()}
    end

    test "of the creator who never entered makes the Account the Host, with no seat to move" do
      room = enter!(room(), "guest:dana", "Dana")

      assert {:ok, room} = Room.move_seat(room, @host, @account)

      assert room.host_id == @account
      assert %{host?: true, me: nil, can_start?: false} = Room.view_for(room, @account)

      room = enter!(room, @account, "Malika")

      assert people(room, @account) == [{1, "Dana", false, false}, {2, "Malika", true, true}]
    end

    test "in the lobby gives the Account the seat: the number, Nickname, Host, Tally, sitting out and Away" do
      room =
        %{lobby() | tally: %{@host => 2, "guest:dana" => 1}}
        |> sit_out!(@host)
        |> Room.away(@host, 1_000)

      assert {:moved, room} = Room.move_seat(room, @host, @account)

      refute Room.member?(room, @host)
      assert Room.member?(room, @account)
      assert room.host_id == @account
      assert room.tally == %{@account => 2, "guest:dana" => 1}
      assert room.away == %{@account => 1_000}
      assert Room.dealt_in(room) == ["guest:timur", "guest:dana"]

      assert %{me: "Malika", host?: true, sitting_out?: true} = Room.view_for(room, @account)
      assert %{me: nil, host?: false} = Room.view_for(room, @host)

      assert people(room, @account) ==
               [{1, "Timur", false, false}, {2, "Malika", true, true}, {3, "Dana", false, false}]

      assert people(room, "guest:dana") ==
               [{1, "Timur", false, false}, {2, "Malika", true, false}, {3, "Dana", false, true}]

      assert %{nickname: "Malika", tally: 2, sitting_out?: true} =
               Enum.at(Room.view_for(room, "guest:dana").people, 1)
    end

    test "of a Guest in a Room their Account created and never entered keeps the Account Host" do
      room = "KQXT" |> Room.new(@account) |> enter!("guest:dana", "Dana")

      assert {:moved, room} = Room.move_seat(room, "guest:dana", @account)

      assert room.host_id == @account
      assert people(room, @account) == [{1, "Dana", true, true}]
    end

    test "mid-bidding, the Account holds the same dice and the turn, and the others see the same Nickname" do
      {:ok, before} = Room.raise(playing(), "guest:dana", 1, 6)

      assert {:moved, room} = Room.move_seat(before, "guest:timur", @account)

      mine = Room.view_for(room, @account).game
      assert %{seated?: true, my_dice: [2], my_turn?: true, can_check?: true} = mine
      assert mine.turn == %{nickname: "Timur", me?: true, n: 1}
      assert mine.seats == Room.view_for(before, "guest:timur").game.seats

      assert Room.view_for(room, "guest:dana") == Room.view_for(before, "guest:dana")
      assert Room.view_for(room, @host) == Room.view_for(before, @host)

      assert Room.raise(room, "guest:timur", 2, 6) == {:error, :not_your_turn}

      assert {:ok, %{game: %{turn: @host, bid: %{by: @account}}}} =
               Room.raise(room, @account, 2, 6)
    end

    test "mid-reveal, the Check plays out with the Account as its loser" do
      before = dana_loses(%{})

      assert {:moved, room} = Room.move_seat(before, "guest:dana", @account)

      assert Room.view_for(room, "guest:timur") == Room.view_for(before, "guest:timur")

      {:ok, room} = Room.reveal(room, 1, 3)

      assert %{loser: %{nickname: "Dana", me?: true}} = Room.view_for(room, @account).game.reveal
      assert room.game.counts == %{@account => 2, "guest:timur" => 1, @host => 1}
    end

    test "after a Game over, the Placement and the Tally name the Account" do
      before = over()

      assert {:moved, room} = Room.move_seat(before, "guest:timur", @account)

      assert room.last.placement == [@account, "guest:dana", @host]
      assert room.tally == %{@account => 1}
      assert %{winner: %{nickname: "Timur", me?: true}} = Room.view_for(room, @account).over
      assert Room.view_for(room, "guest:dana").over == Room.view_for(before, "guest:dana").over
    end

    test "when the Account has a seat, the Guest's seat leaves, the Host role and the Tally going to the Account" do
      room = %{enter!(lobby(), @account, "Aziz") | tally: %{@host => 2, @account => 1}}
      room = Room.away(room, @host, 1_000)

      assert {:ok, room} = Room.move_seat(room, @host, @account)

      refute Room.member?(room, @host)
      assert room.host_id == @account
      assert room.tally == %{@account => 3}
      assert room.away == %{}

      assert people(room, @account) ==
               [{1, "Timur", false, false}, {3, "Dana", false, false}, {4, "Aziz", true, true}]
    end

    defp four_playing do
      room = enter!(lobby(), @account, "Aziz")
      seats = ["guest:dana", "guest:timur", @host, @account]
      {:ok, room} = Room.start_game(room, @host, seats)

      Room.start_round(room, %{
        "guest:dana" => [6],
        "guest:timur" => [2],
        @host => [6],
        @account => [1]
      })
    end

    test "when the Account has a seat mid-bidding, the Guest's seat is Knocked out and the Round voided" do
      assert {:roll, room} = Room.move_seat(four_playing(), "guest:timur", @account)

      refute Room.member?(room, "guest:timur")
      assert %{out: ["guest:timur"], voided_by: "guest:timur", dice: %{}} = room.game
      assert Room.view_for(room, @account).playing?
    end

    test "when the Account has a seat mid-reveal, the Check stands" do
      {:ok, room} = Room.raise(four_playing(), "guest:dana", 1, 6)
      {:ok, room} = Room.check(room, "guest:timur")

      assert {:ok, room} = Room.move_seat(room, "guest:dana", @account)

      assert %{out: ["guest:dana"], reveal: %{step: 0, loser: "guest:timur"}} = room.game
    end

    test "when the Account holds the other seat of the last two, the Game ends and the Account wins" do
      room = enter!(lobby(), @account, "Aziz")

      {:ok, room} =
        room
        |> sit_out!(@host)
        |> sit_out!("guest:timur")
        |> Room.start_game(@host, ["guest:dana", @account])

      room = Room.start_round(room, %{"guest:dana" => [6], @account => [1]})

      assert {:ok, room} = Room.move_seat(room, "guest:dana", @account)

      assert room.game == nil
      assert room.tally == %{@account => 1}
      assert room.last.placement == [@account, "guest:dana"]
    end

    defp account_knocked_out do
      {:roll, room} = Room.leave(four_playing(), @account, [])
      Room.start_round(room, %{"guest:dana" => [5], "guest:timur" => [2], @host => [3]})
    end

    test "when the Account left a Knocked-out seat, the two seats swap, nobody's number moving" do
      before = %{account_knocked_out() | tally: %{"guest:dana" => 1, @account => 2}}
      before = Room.away(before, "guest:dana", 1_000)

      assert {:moved, room} = Room.move_seat(before, "guest:dana", @account)

      assert Room.member?(room, @account)
      refute Room.member?(room, "guest:dana")
      assert room.tally == %{@account => 3}
      assert room.away == %{@account => 1_000}

      assert %{seats: [@account, "guest:timur", @host, "guest:dana"], out: ["guest:dana"]} =
               room.game

      mine = Room.view_for(room, @account)
      assert %{me: "Dana", playing?: true} = mine
      assert %{seated?: true, my_dice: [5], my_turn?: true} = mine.game
      assert mine.game.seats == Room.view_for(before, "guest:dana").game.seats

      theirs = Room.view_for(room, "guest:timur")
      assert theirs.game == Room.view_for(before, "guest:timur").game
      assert theirs.away == %{3 => 1_000}

      assert for(p <- theirs.people, do: {p.n, p.nickname, p.tally}) ==
               [{1, "Timur", 0}, {2, "Malika", 0}, {3, "Dana", 3}]

      assert Room.enter(room, "guest:bek", "Aziz") == {:taken, "Aziz", "Aziz 2"}
    end

    test "of the vote's starter carries the vote: they still asked, by their Nickname, and their yes counts" do
      assert {:moved, room} = Room.move_seat(voting(), "guest:dana", @account)

      for viewer <- [@host, "guest:timur", @account, "guest:dana"],
          do: Room.view_for(room, viewer)

      assert %{by: %{nickname: "Dana", me?: false, n: 3}, yes: 1, of: 2} =
               host_away_view(room, "guest:timur").vote

      assert %{by: %{me?: true}, said_yes?: true} = host_away_view(room, @account).vote
      assert settle(vote!(room, "guest:timur")).host_id == "guest:timur"
    end

    test "onto an Account with a seat, a yes said from both counts once, as the Account's, and the vote passes" do
      room = lobby() |> enter!(@account, "Aziz") |> voting() |> vote!("guest:timur")

      assert {:ok, room} = room |> vote!(@account) |> Room.move_seat("guest:timur", @account)

      assert room.handover.vote.yes == ["guest:dana", @account]

      room = lobby() |> enter!(@account, "Aziz") |> voting() |> vote!("guest:timur")

      assert {:ok, room} = Room.move_seat(room, "guest:timur", @account)

      assert %{yes: 2, of: 2, said_yes?: true} = host_away_view(room, @account).vote
      assert settle(room).host_id == "guest:dana"
    end

    test "of the Host who is Away keeps the handover running and its vote open" do
      before = voting()

      assert {:moved, room} = Room.move_seat(before, @host, @account)

      assert host_away_view(room, @account) == nil
      assert host_away_view(room, "guest:dana") == host_away_view(before, "guest:dana")

      assert Room.settle_handover(room, 50_000, &no_shuffle/1).handover ==
               %{before.handover | host: @account}
    end
  end
end
