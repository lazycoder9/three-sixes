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
               %{nickname: "Timur", host?: false, me?: false, n: 1},
               %{nickname: "Malika", host?: true, me?: false, n: 2},
               %{nickname: "Dana", host?: false, me?: true, n: 3}
             ],
             me: "Dana",
             host?: false,
             host_nickname: "Malika",
             can_start?: false,
             dealt_in: 3,
             game: nil
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
                   penalty?: false
                 },
                 %{
                   person: @malika,
                   dice: 1,
                   said: nil,
                   on_turn?: false,
                   faces: nil,
                   penalty?: false
                 },
                 %{
                   person: @dana,
                   dice: 1,
                   said: %{count: 1, face: 6},
                   on_turn?: false,
                   faces: nil,
                   penalty?: false
                 }
               ],
               reveal: nil
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
               loser: nil
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
                   penalty?: true
                 },
                 %{
                   person: @malika,
                   dice: 1,
                   said: nil,
                   on_turn?: false,
                   faces: [6],
                   penalty?: false
                 },
                 %{
                   person: @dana,
                   dice: 1,
                   said: %{count: 1, face: 6},
                   on_turn?: false,
                   faces: [6],
                   penalty?: false
                 }
               ],
               reveal: %{
                 step: 3,
                 checker: @timur,
                 bid: %{count: 1, face: 6, by: @dana},
                 count: 2,
                 stood?: true,
                 loser: @timur
               }
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
end
