defmodule ThreeSixes.RoomsTest do
  use ThreeSixes.DataCase, async: false

  import ExUnit.CaptureLog

  alias ThreeSixes.Dice.Scripted
  alias ThreeSixes.Records.GameRecord
  alias ThreeSixes.Room
  alias ThreeSixes.RoomCode
  alias ThreeSixes.Rooms
  alias ThreeSixes.Rooms.Save
  alias ThreeSixes.Rooms.Server

  @host "guest:host"
  @address "203.0.113.7"

  setup do
    on_exit(&close_every_room/0)
  end

  defp join_from_another_process(code, person_id) do
    test = self()

    pid =
      spawn(fn ->
        send(test, {:joined, self(), Rooms.join(code, person_id)})
        forward(test)
      end)

    assert_receive {:joined, ^pid, {:ok, _view}}
    pid
  end

  defp table do
    {:ok, code} = Rooms.create(@host, @address)
    {:ok, _view} = Rooms.join(code, @host)
    {:ok, _view} = Rooms.enter(code, @host, "Malika")
    {:ok, _view} = Rooms.enter(code, "guest:dana", "Dana")
    dana = join_from_another_process(code, "guest:dana")
    flush_views()
    {code, dana}
  end

  defp flush_views do
    receive do
      {:room_view, _view} -> flush_views()
      {:forwarded, _pid, {:room_view, _view}} -> flush_views()
    after
      0 -> :ok
    end
  end

  defp forward(test) do
    receive do
      message -> send(test, {:forwarded, self(), message})
    end

    forward(test)
  end

  test "creating a Room opens it under its code with the creator as Host" do
    {:ok, code} = Rooms.create(@host, @address)

    assert RoomCode.valid?(code)
    assert is_pid(Rooms.whereis(code))
    assert {:ok, %{code: ^code, host?: true, me: nil, people: []}} = Rooms.join(code, @host)
  end

  test "with every Room open, creating one is refused as busy" do
    for code <- fill_every_room(), do: open_until_exit(code)

    assert Rooms.create(@host, @address) == {:error, :busy}
  end

  test "creating gives up as busy after ten codes that are all taken" do
    :rand.seed(:exsss, {17, 17, 17})
    taken = for _attempt <- 1..10, do: RoomCode.random()

    for code <- taken do
      DynamicSupervisor.start_child(
        ThreeSixes.Rooms.Supervisor,
        {Server, {code, {"guest:" <> code, code}, []}}
      )

      open_until_exit(code)
    end

    :rand.seed(:exsss, {17, 17, 17})
    assert Rooms.create(@host, @address) == {:error, :busy}
  end

  test "a Guest's sixth open Room is refused, and allowed again once one of the five closes" do
    codes = for _room <- 1..5, do: elem(Rooms.create(@host, @address), 1)

    assert Rooms.create(@host, "198.51.100.1") == {:error, :too_many}

    codes |> hd() |> close()

    assert {:ok, _code} = Rooms.create(@host, @address)
  end

  test "twenty Guests on one address open twenty Rooms and a twenty-first is refused" do
    for guest <- 1..20, do: assert({:ok, _code} = Rooms.create("guest:#{guest}", @address))

    assert Rooms.create("guest:new", @address) == {:error, :too_many}
    assert {:ok, _code} = Rooms.create("guest:new", "198.51.100.1")
  end

  test "joining a code with no open Room is closed" do
    {:ok, code} = Rooms.create(@host, @address)
    :ok = GenServer.stop(Rooms.whereis(code))

    assert Rooms.join(code, @host) == {:error, :closed}
    assert Rooms.join("AEIO", @host) == {:error, :closed}
  end

  test "after a person enters, every joined process gets its own view, the one who entered included" do
    {:ok, code} = Rooms.create(@host, @address)
    {:ok, _view} = Rooms.join(code, @host)
    dana = join_from_another_process(code, "guest:dana")

    assert {:ok, %{me: "Dana", people: [%{nickname: "Dana", me?: true}]}} =
             Rooms.enter(code, "guest:dana", "Dana")

    assert_receive {:room_view,
                    %{me: nil, host?: true, people: [%{nickname: "Dana", me?: false}]}}

    assert_receive {:forwarded, ^dana, {:room_view, %{me: "Dana", host?: false}}}
  end

  test "an enter that changes nothing sends nothing" do
    {:ok, code} = Rooms.create(@host, @address)
    {:ok, _view} = Rooms.join(code, @host)
    {:ok, _view} = Rooms.enter(code, "guest:dana", "Dana")
    assert_receive {:room_view, _view}

    assert {:ok, %{me: "Dana"}} = Rooms.enter(code, "guest:dana", "Dana")
    assert {:taken, "Dana", "Dana 2"} = Rooms.enter(code, "guest:other", "dana")
    assert {:error, :blank} = Rooms.enter(code, "guest:other", " ")
    refute_receive {:room_view, _view}
  end

  test "a process that joins twice is monitored once and gets one view per change" do
    {:ok, code} = Rooms.create(@host, @address)
    {:ok, _view} = Rooms.join(code, @host)
    {:ok, _view} = Rooms.join(code, @host)

    assert Process.info(Rooms.whereis(code), :monitors) == {:monitors, [process: self()]}

    {:ok, _view} = Rooms.enter(code, "guest:dana", "Dana")
    assert_receive {:room_view, _view}
    refute_receive {:room_view, _view}
  end

  test "a joined process that dies is forgotten and the others still get updates" do
    {:ok, code} = Rooms.create(@host, @address)
    {:ok, _view} = Rooms.join(code, @host)
    timur = join_from_another_process(code, "guest:timur")
    ref = Process.monitor(timur)
    Process.exit(timur, :kill)
    assert_receive {:DOWN, ^ref, :process, ^timur, :killed}

    {:ok, _view} = Rooms.enter(code, "guest:dana", "Dana")

    assert_receive {:room_view, %{people: [%{nickname: "Dana"}]}}
    assert Process.info(Rooms.whereis(code), :monitors) == {:monitors, [process: self()]}
  end

  test "a Room nobody has joined closes on its timeout" do
    {:ok, code} = Rooms.create(@host, @address)
    room = Rooms.whereis(code)
    ref = Process.monitor(room)

    send(room, close_timeout(room))

    assert_receive {:DOWN, ^ref, :process, ^room, :normal}
    assert Rooms.join(code, @host) == {:error, :closed}
  end

  test "a Room with someone joined ignores the timeout" do
    {:ok, code} = Rooms.create(@host, @address)
    room = Rooms.whereis(code)
    timeout = close_timeout(room)
    {:ok, _view} = Rooms.join(code, @host)

    send(room, timeout)

    assert {:ok, _view} = Rooms.join(code, @host)
    assert Rooms.whereis(code) == room
  end

  test "after join, leave, rejoin and leave, only the last leave's timeout closes the Room" do
    {:ok, code} = Rooms.create(@host, @address)
    room = Rooms.whereis(code)
    ref = Process.monitor(room)

    leave(join_from_another_process(code, "guest:dana"))
    first_leave = close_timeout(room)
    leave(join_from_another_process(code, "guest:dana"))
    last_leave = close_timeout(room)

    send(room, first_leave)
    refute_receive {:DOWN, ^ref, :process, ^room, _reason}

    send(room, last_leave)
    assert_receive {:DOWN, ^ref, :process, ^room, :normal}
  end

  test "a join that arrives just behind the timeout finds the Room closed" do
    {:ok, code} = Rooms.create(@host, @address)
    room = Rooms.whereis(code)
    :ok = :sys.suspend(room)
    send(room, close_timeout(room))

    joining = Task.async(fn -> Rooms.join(code, @host) end)
    wait_for_messages(room, 2)
    :ok = :sys.resume(room)

    assert Task.await(joining) == {:error, :closed}
  end

  describe "a Game" do
    test "the Host starts it, the dice roll in seat order, and everyone gets their view" do
      {code, dana} = table()
      Scripted.script([[3], [5]])

      assert Rooms.start_game(code, @host) == :ok

      assert_receive {:room_view,
                      %{game: %{round: 1, my_dice: [3], my_turn?: true, dice_on_table: 2}}}

      assert_receive {:forwarded, ^dana,
                      {:room_view, %{game: %{round: 1, my_dice: [5], my_turn?: false}}}}
    end
  end

  test "a change that passes no Host role leaves the scripted seat order for the Game" do
    {code, dana} = table()
    Scripted.script_seats(["guest:dana", @host])
    :ok = Rooms.sit_out(code, "guest:dana", false)
    Scripted.script([[3], [5]])

    assert Rooms.start_game(code, @host) == :ok

    assert_receive {:forwarded, ^dana,
                    {:room_view, %{game: %{turn: %{nickname: "Dana"}, my_dice: [3]}}}}
  end

  describe "sitting out" do
    test "every joined process gets the flag, and the next Game is dealt to the others" do
      {code, dana} = table()
      {:ok, _view} = Rooms.enter(code, "guest:timur", "Timur")
      flush_views()

      assert Rooms.sit_out(code, "guest:dana", true) == :ok

      assert_receive {:room_view,
                      %{sitting_out?: false, dealt_in: 2, people: [_, %{sitting_out?: true}, _]}}

      assert_receive {:forwarded, ^dana, {:room_view, %{sitting_out?: true}}}

      Scripted.script([[3], [5]])
      :ok = Rooms.start_game(code, @host)

      assert_receive {:room_view, %{game: %{seats: seats}}}
      assert Enum.map(seats, & &1.person.nickname) == ["Malika", "Timur"]

      assert_receive {:forwarded, ^dana,
                      {:room_view,
                       %{
                         game: %{seated?: false, my_dice: nil},
                         spectators: [%{person: %{me?: true}}]
                       }}}
    end
  end

  defp started do
    {code, dana} = table()
    start(code, dana)
    {code, dana}
  end

  defp start(code, dana) do
    Scripted.script([[6], [2]])
    :ok = Rooms.start_game(code, @host)
    assert_receive {:room_view, %{game: %{round: 1}}}
    assert_receive {:forwarded, ^dana, {:room_view, %{game: %{round: 1}}}}
  end

  describe "a Round" do
    test "runs from a Raise and a Check through the reveal to the next Round, opened by the loser" do
      {code, dana} = started()
      room = Rooms.whereis(code)

      assert Rooms.raise(code, @host, 2, 6) == :ok
      assert_receive {:room_view, %{game: %{bid: %{count: 2, face: 6}, my_turn?: false}}}
      assert_receive {:forwarded, ^dana, {:room_view, %{game: %{my_turn?: true}}}}

      assert Rooms.check(code, "guest:dana") == :ok
      assert_receive {:room_view, %{game: %{reveal: %{step: 0}}}}

      send(room, {:reveal, 1, 1})
      assert_receive {:room_view, %{game: %{reveal: %{step: 1}, seats: [_, %{faces: [2]}]}}}

      send(room, {:reveal, 1, 2})
      assert_receive {:room_view, %{game: %{reveal: %{step: 2, count: 1, stood?: false}}}}

      send(room, {:reveal, 1, 3})

      assert_receive {:room_view,
                      %{game: %{reveal: %{step: 3, loser: %{me?: true}}, dice_on_table: 3}}}

      Scripted.script([[1, 4], [5]])
      send(room, {:next_round, 1})

      assert_receive {:room_view,
                      %{game: %{round: 2, my_dice: [1, 4], my_turn?: true, reveal: nil}}}

      assert_receive {:forwarded, ^dana,
                      {:room_view, %{game: %{round: 2, my_dice: [5], dice_on_table: 3}}}}
    end
  end

  defp knock_out_the_host(code) do
    room = Rooms.whereis(code)
    Scripted.script([[1], [2]])
    :ok = Rooms.start_game(code, @host)

    for round <- 1..5 do
      if round > 1 do
        Scripted.script([List.duplicate(1, round), [2]])
        send(room, {:next_round, round - 1})
      end

      :ok = Rooms.raise(code, @host, round + 1, 5)
      :ok = Rooms.check(code, "guest:dana")
      send(room, {:reveal, round, 3})
    end

    flush_after(room)
    room
  end

  describe "Game over" do
    test "after the last Knock out the next Round ends the Game, rolling nothing" do
      {code, dana} = table()
      room = knock_out_the_host(code)

      send(room, {:next_round, 5})

      malika = %{nickname: "Malika", me?: true, n: 1}
      dana_ref = %{nickname: "Dana", me?: false, n: 2}

      assert_receive {:room_view, %{game: nil, over: over, people: [%{tally: 0}, %{tally: 1}]}}

      assert over == %{winner: dana_ref, placement: [dana_ref, malika], rounds: 5}
      assert_receive {:forwarded, ^dana, {:room_view, %{over: %{winner: %{me?: true}}}}}
      assert Rooms.whereis(code) == room
    end

    test "the Host's Next Game deals everyone in again, at one die, in reshuffled seats" do
      {code, dana} = table()
      room = knock_out_the_host(code)
      send(room, {:next_round, 5})
      flush_after(room)

      Scripted.script_seats(["guest:dana", @host])
      Scripted.script([[3], [4]])

      assert Rooms.start_game(code, @host) == :ok

      assert_receive {:room_view, %{over: nil, game: %{round: 1, my_dice: [4], my_turn?: false}}}

      assert_receive {:forwarded, ^dana,
                      {:room_view, %{game: %{round: 1, my_dice: [3], my_turn?: true}}}}
    end
  end

  defp recorded do
    for game <- GameRecord |> Repo.all() |> Repo.preload([:placements, :checks]) do
      %{
        room_code: game.room_code,
        rounds: game.rounds,
        placements:
          game.placements |> Enum.sort_by(& &1.place) |> Enum.map(&{&1.person_id, &1.nickname}),
        checks:
          game.checks
          |> Enum.sort_by(& &1.round)
          |> Enum.map(&{&1.round, &1.checker_id, &1.bidder_id, &1.stood})
      }
    end
  end

  describe "recording" do
    test "a Game played to its end is recorded once, with its Placements, Nicknames and Checks" do
      {code, _dana} = table()
      room = Rooms.whereis(code)
      Scripted.script([[6], [2]])
      :ok = Rooms.start_game(code, @host)
      :ok = Rooms.raise(code, @host, 1, 6)
      :ok = Rooms.raise(code, "guest:dana", 2, 2)
      :ok = Rooms.check(code, @host)
      send(room, {:reveal, 1, 3})

      Scripted.script([[1], [2, 2]])
      send(room, {:next_round, 1})
      :ok = Rooms.raise(code, "guest:dana", 2, 2)
      :ok = Rooms.check(code, @host)
      send(room, {:reveal, 2, 3})

      for round <- 3..6 do
        Scripted.script([List.duplicate(1, round - 1), [2, 2]])
        send(room, {:next_round, round - 1})
        :ok = Rooms.raise(code, @host, round + 1, 6)
        :ok = Rooms.check(code, "guest:dana")
        send(room, {:reveal, round, 3})
      end

      send(room, {:next_round, 6})
      flush_after(room)
      :ok = Rooms.sit_out(code, "guest:dana", true)
      send(room, {:next_round, 6})
      flush_after(room)

      assert recorded() == [
               %{
                 room_code: code,
                 rounds: 6,
                 placements: [{"guest:dana", "Dana"}, {@host, "Malika"}],
                 checks:
                   [{1, @host, "guest:dana", false}, {2, @host, "guest:dana", true}] ++
                     for(round <- 3..6, do: {round, "guest:dana", @host, false})
               }
             ]
    end

    test "a Game ended by a leave is recorded, the leaver placed with their Nickname" do
      {code, _dana} = started()
      room = Rooms.whereis(code)
      :ok = Rooms.raise(code, @host, 1, 6)
      :ok = Rooms.check(code, "guest:dana")
      send(room, {:reveal, 1, 3})

      assert Rooms.leave(code, "guest:dana") == :ok

      assert recorded() == [
               %{
                 room_code: code,
                 rounds: 1,
                 placements: [{@host, "Malika"}, {"guest:dana", "Dana"}],
                 checks: [{1, "guest:dana", @host, true}]
               }
             ]
    end

    test "a Room that closes mid-Game records nothing" do
      {:ok, code} = Rooms.create(@host, @address)
      {:ok, _view} = Rooms.enter(code, @host, "Malika")
      {:ok, _view} = Rooms.enter(code, "guest:dana", "Dana")
      room = Rooms.whereis(code)
      ref = Process.monitor(room)
      Scripted.script([[6], [2]])
      :ok = Rooms.start_game(code, @host)
      :ok = Rooms.raise(code, @host, 1, 6)
      :ok = Rooms.check(code, "guest:dana")
      send(room, {:reveal, 1, 3})
      flush_after(room)

      send(room, close_timeout(room))

      assert_receive {:DOWN, ^ref, :process, ^room, :normal}
      assert recorded() == []
    end

    test "a record that cannot be written is logged, and the Room plays on" do
      {code, dana} = started()
      room = Rooms.whereis(code)
      Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)

      log = capture_log(fn -> assert Rooms.leave(code, "guest:dana") == :ok end)

      assert log =~ "Game in Room #{code} not recorded"
      assert_receive {:room_view, %{over: %{winner: %{nickname: "Malika"}}}}
      assert_receive {:forwarded, ^dana, {:room_view, %{me: nil}}}
      assert Rooms.whereis(code) == room
      assert {:ok, %{over: %{rounds: 1}}} = Rooms.join(code, @host)

      assert capture_log(&close_every_room/0) =~ "could not write its save"
    end

    test "a Game a restore finishes is recorded once, and not again from the save after it" do
      {code, _dana} = table()
      knock_out_the_host(code)
      shut_down(code)
      assert recorded() == []

      assert Rooms.sit_out(code, "guest:aziz", true) == {:error, :not_member}

      assert recorded() == [
               %{
                 room_code: code,
                 rounds: 5,
                 placements: [{"guest:dana", "Dana"}, {@host, "Malika"}],
                 checks: for(round <- 1..5, do: {round, "guest:dana", @host, false})
               }
             ]

      shut_down(code)
      assert Rooms.sit_out(code, "guest:aziz", true) == {:error, :not_member}

      assert length(recorded()) == 1
    end
  end

  describe "a Reaction" do
    test "reaches every joined process, says who sent it from each side, and sends no view" do
      {code, dana} = table()

      assert Rooms.react(code, "guest:dana", "gg") == :ok

      assert_receive {:reaction, %{by: %{nickname: "Dana", me?: false, n: 2}, key: "gg"}}

      assert_receive {:forwarded, ^dana,
                      {:reaction, %{by: %{nickname: "Dana", me?: true, n: 2}, key: "gg"}}}

      refute_receive {:room_view, _view}
      refute_receive {:forwarded, _pid, {:room_view, _view}}
    end

    test "a second within the wait is refused and reaches nobody; once it ends the next goes" do
      {code, dana} = table()
      :ok = Rooms.react(code, "guest:dana", "gg")
      assert_receive {:reaction, _reaction}
      assert_receive {:forwarded, ^dana, {:reaction, _reaction}}

      assert Rooms.react(code, "guest:dana", "lol") == {:error, :too_soon}
      refute_receive {:reaction, _reaction}
      refute_receive {:forwarded, ^dana, {:reaction, _reaction}}

      send(Rooms.whereis(code), {:reaction_ready, "guest:dana"})

      assert Rooms.react(code, "guest:dana", "lol") == :ok
      assert_receive {:reaction, %{by: %{nickname: "Dana"}, key: "lol"}}
    end

    test "one person's wait does not hold up another" do
      {code, dana} = table()
      :ok = Rooms.react(code, "guest:dana", "gg")

      assert Rooms.react(code, @host, "fire") == :ok

      assert_receive {:forwarded, ^dana,
                      {:reaction, %{by: %{nickname: "Malika", me?: false}, key: "fire"}}}
    end

    test "from someone not in the Room, or outside the set, is refused and reaches nobody" do
      {code, dana} = table()
      {:ok, _view} = Rooms.join(code, "guest:aziz")

      assert Rooms.react(code, "guest:aziz", "gg") == {:error, :not_member}
      assert Rooms.react(code, "guest:dana", "wave") == {:error, :unknown}
      assert Rooms.react(code, "guest:dana", nil) == {:error, :unknown}
      refute_receive {:reaction, _reaction}
      refute_receive {:forwarded, ^dana, {:reaction, _reaction}}

      assert Rooms.react(code, "guest:dana", "gg") == :ok
    end

    test "goes through during the reveal and leaves the Room as it was" do
      {code, dana} = started()
      room = Rooms.whereis(code)
      :ok = Rooms.raise(code, @host, 1, 6)
      :ok = Rooms.check(code, "guest:dana")
      send(room, {:reveal, 1, 1})
      flush_after(room)
      before = :sys.get_state(room).room

      assert Rooms.react(code, @host, "gasp") == :ok

      assert_receive {:forwarded, ^dana, {:reaction, %{by: %{nickname: "Malika"}, key: "gasp"}}}
      assert :sys.get_state(room).room == before
      refute_receive {:room_view, _view}
    end
  end

  describe "stale and refused" do
    test "a reveal or next-round message for another Round, or none running, changes nothing" do
      {code, _dana} = started()
      room = Rooms.whereis(code)

      assert_ignored(room, [{:reveal, 1, 1}, {:next_round, 1}])

      :ok = Rooms.raise(code, @host, 1, 6)
      :ok = Rooms.check(code, "guest:dana")
      Scripted.script([[1], [5, 5]])
      send(room, {:next_round, 1})
      flush_after(room)

      assert_ignored(room, [{:reveal, 1, 3}, {:next_round, 1}])

      :ok = Rooms.raise(code, "guest:dana", 1, 5)
      :ok = Rooms.check(code, @host)
      flush_after(room)

      assert_ignored(room, [{:reveal, 1, 3}, {:next_round, 1}, {:reveal, 3, 3}])

      assert %{round: 2, reveal: %{step: 0}, counts: %{"guest:dana" => 2, @host => 1}} =
               :sys.get_state(room).room.game
    end

    test "a reveal step already reached sends nothing" do
      {code, _dana} = started()
      room = Rooms.whereis(code)
      :ok = Rooms.raise(code, @host, 1, 6)
      :ok = Rooms.check(code, "guest:dana")
      send(room, {:reveal, 1, 2})
      flush_after(room)

      assert_ignored(room, [{:reveal, 1, 1}, {:reveal, 1, 2}])
    end

    test "a refused start, Raise, Check or sitting out replies an error and sends no view" do
      {code, dana} = table()

      assert Rooms.raise(code, @host, 1, 6) == {:error, :not_bidding}
      assert Rooms.check(code, @host) == {:error, :not_bidding}
      assert Rooms.start_game(code, "guest:dana") == {:error, :not_host}
      assert Rooms.sit_out(code, "guest:aziz", true) == {:error, :not_member}
      refute_receive {:room_view, _view}

      start(code, dana)

      assert Rooms.start_game(code, @host) == {:error, :playing}
      assert Rooms.check(code, @host) == {:error, :no_bid}
      assert Rooms.raise(code, "guest:dana", 1, 6) == {:error, :not_your_turn}
      assert Rooms.raise(code, @host, 3, 6) == {:error, :illegal}
      assert Rooms.raise(code, @host, "2", 6) == {:error, :illegal}
      refute_receive {:room_view, _view}
      refute_receive {:forwarded, _pid, {:room_view, _view}}
    end

    test "a Game needs two people" do
      {:ok, code} = Rooms.create(@host, @address)
      {:ok, _view} = Rooms.enter(code, @host, "Malika")

      assert Rooms.start_game(code, @host) == {:error, :too_few}
    end

    test "a closed Room is closed to a Game and to Reactions too" do
      {:ok, code} = Rooms.create(@host, @address)
      close(code)

      assert Rooms.start_game(code, @host) == {:error, :closed}
      assert Rooms.raise(code, @host, 1, 6) == {:error, :closed}
      assert Rooms.check(code, @host) == {:error, :closed}
      assert Rooms.sit_out(code, @host, true) == {:error, :closed}
      assert Rooms.react(code, @host, "gg") == {:error, :closed}
    end
  end

  describe "leaving" do
    test "takes the person out of the Room and every joined process gets its view" do
      {code, dana} = table()

      assert Rooms.leave(code, "guest:dana") == :ok

      assert_receive {:room_view, %{people: [%{nickname: "Malika"}]}}
      assert_receive {:forwarded, ^dana, {:room_view, %{me: nil, people: [_]}}}
    end

    test "mid-reveal leaves the Check standing: the reveal runs on to the loser's Penalty die" do
      {code, dana} = table()
      {:ok, _view} = Rooms.enter(code, "guest:timur", "Timur")
      room = Rooms.whereis(code)
      Scripted.script([[6], [2], [3]])
      :ok = Rooms.start_game(code, @host)
      :ok = Rooms.raise(code, @host, 2, 6)
      :ok = Rooms.check(code, "guest:dana")
      send(room, {:reveal, 1, 1})
      flush_after(room)

      assert Rooms.leave(code, "guest:timur") == :ok

      assert_receive {:room_view, %{game: %{round: 1, reveal: %{step: 1}, seats: seats}}}
      assert [false, false, true] == Enum.map(seats, & &1.out?)

      send(room, {:reveal, 1, 3})
      Scripted.script([[4, 4], [5]])
      send(room, {:next_round, 1})

      assert_receive {:room_view, %{game: %{round: 2, my_dice: [4, 4], my_turn?: true}}}
      assert_receive {:forwarded, ^dana, {:room_view, %{game: %{round: 2, dice_on_table: 3}}}}
    end

    test "mid-reveal by one of the last two ends the Game, its reveal's timers reaching no other" do
      {code, _dana} = table()
      room = Rooms.whereis(code)
      Scripted.script([[6], [2]])
      :ok = Rooms.start_game(code, @host)
      :ok = Rooms.raise(code, @host, 1, 6)
      :ok = Rooms.check(code, "guest:dana")

      assert Rooms.leave(code, "guest:dana") == :ok
      assert %{game: nil} = :sys.get_state(room).room

      Process.sleep(900)
      {:ok, _view} = Rooms.enter(code, "guest:dana", "Dana")
      Scripted.script([[6], [2]])
      :ok = Rooms.start_game(code, @host)
      :ok = Rooms.raise(code, @host, 1, 6)
      :ok = Rooms.check(code, "guest:dana")
      flush_after(room)

      refute_receive {:room_view, %{game: %{reveal: %{step: 1}}}}, 600
    end

    test "by the Host passes the role to someone connected, in the order shuffled" do
      {code, dana} = table()
      {:ok, _view} = Rooms.enter(code, "guest:timur", "Timur")
      {:ok, _view} = Rooms.enter(code, "guest:aziz", "Aziz")
      timur = join_from_another_process(code, "guest:timur")
      flush_views()
      Scripted.script_seats([@host, "guest:timur", "guest:dana"])

      assert Rooms.leave(code, @host) == :ok

      assert_receive {:forwarded, ^timur, {:room_view, %{host?: true}}}
      assert_receive {:forwarded, ^dana, {:room_view, %{host?: false, host_nickname: "Timur"}}}
    end
  end

  describe "the Host removing someone" do
    test "tells each of the removed person's processes, before any view, and the rest see it" do
      {code, dana} = table()
      dana_again = join_from_another_process(code, "guest:dana")

      assert Rooms.remove(code, @host, 2) == :ok

      assert_receive {:room_view, %{people: [%{nickname: "Malika"}]}}

      for pid <- [dana, dana_again] do
        assert_receive {:forwarded, ^pid, first}
        assert first == :removed
        assert_receive {:forwarded, ^pid, {:room_view, %{me: nil}}}
      end
    end
  end

  describe "handing over the Host role" do
    test "makes the new Host, and every joined process gets its view" do
      {code, dana} = table()

      assert Rooms.make_host(code, @host, 2) == :ok

      assert_receive {:room_view, %{host?: false, host_nickname: "Dana"}}
      assert_receive {:forwarded, ^dana, {:room_view, %{host?: true, can_start?: true}}}
      assert Rooms.start_game(code, @host) == {:error, :not_host}
    end
  end

  describe "Away" do
    test "a member's last process exiting makes them Away at the Room's clock, and the rest see it" do
      {code, dana} = table()
      room = Rooms.whereis(code)
      :sys.replace_state(room, &%{&1 | now: fn -> 1_000 end})

      leave(dana)

      assert_receive {:room_view, %{away: %{2 => 1_000}, dealt_in: 1}}
    end

    test "one of two processes exiting leaves the person not Away, and sends nothing" do
      {code, dana} = table()
      _dana_again = join_from_another_process(code, "guest:dana")

      leave(dana)

      :sys.get_state(Rooms.whereis(code))
      refute_receive {:room_view, _view}
    end

    test "joining again ends being Away, and every other joined process is told" do
      {code, dana} = table()
      leave(dana)
      assert_receive {:room_view, %{away: %{2 => since}}}
      assert_in_delta since, System.system_time(:millisecond), 1_000

      dana = join_from_another_process(code, "guest:dana")

      assert_receive {:room_view, %{away: away, dealt_in: 2}}
      assert away == %{}
      refute_receive {:forwarded, ^dana, {:room_view, _view}}
    end

    test "a restored Room has every member Away until they join again" do
      {code, _dana} = table()
      shut_down(code)

      assert Rooms.sit_out(code, "guest:aziz", true) == {:error, :not_member}
      assert %{away: away} = :sys.get_state(Rooms.whereis(code)).room
      assert away |> Map.keys() |> Enum.sort() == Enum.sort([@host, "guest:dana"])

      assert {:ok, %{away: %{2 => _since}, dealt_in: 1}} = Rooms.join(code, @host)

      _dana = join_from_another_process(code, "guest:dana")

      assert_receive {:room_view, %{away: away, dealt_in: 2}}
      assert away == %{}
    end

    test "the process of someone who never entered exiting sends nothing" do
      {code, _dana} = table()

      leave(join_from_another_process(code, "guest:aziz"))

      :sys.get_state(Rooms.whereis(code))
      refute_receive {:room_view, _view}
    end
  end

  describe "the Host Away" do
    defp host_away do
      {:ok, code} = Rooms.create(@host, @address)
      {:ok, _view} = Rooms.enter(code, @host, "Malika")
      {:ok, _view} = Rooms.enter(code, "guest:dana", "Dana")
      {:ok, _view} = Rooms.enter(code, "guest:timur", "Timur")
      host = join_from_another_process(code, @host)
      dana = join_from_another_process(code, "guest:dana")
      timur = join_from_another_process(code, "guest:timur")
      room = Rooms.whereis(code)
      :sys.replace_state(room, &%{&1 | now: fn -> 1_000 end})
      leave(host)
      flush_after(room)
      {code, room, dana, timur}
    end

    defp timeout(room, key, message) do
      assert {timer, _ends_at} = Map.fetch!(:sys.get_state(room), key)
      {:timeout, timer, message}
    end

    test "the Host's last process exiting arms the handover for 2 minutes on, and the rest see it" do
      {:ok, code} = Rooms.create(@host, @address)
      {:ok, _view} = Rooms.enter(code, @host, "Malika")
      {:ok, _view} = Rooms.enter(code, "guest:dana", "Dana")
      host = join_from_another_process(code, @host)
      dana = join_from_another_process(code, "guest:dana")
      room = Rooms.whereis(code)
      :sys.replace_state(room, &%{&1 | now: fn -> 1_000 end})

      leave(host)

      assert_receive {:forwarded, ^dana,
                      {:room_view, %{host_away: %{since: 1_000, ends_at: 121_000, vote: nil}}}}

      assert %{handover_timer: {timer, 121_000}, vote_timer: nil} = :sys.get_state(room)
      assert :erlang.read_timer(timer) in 119_000..120_000
    end

    test "the handover timeout hands the role to someone connected, and every process sees it" do
      {_code, room, dana, timur} = host_away()
      Scripted.script_seats(["guest:timur", "guest:dana"])

      send(room, timeout(room, :handover_timer, :handover))

      assert_receive {:forwarded, ^timur, {:room_view, %{host?: true, host_away: nil}}}

      assert_receive {:forwarded, ^dana, {:room_view, %{host_nickname: "Timur", host_away: nil}}}

      assert %{handover_timer: nil, room: %{host_id: "guest:timur"}} = :sys.get_state(room)
    end

    test "a stale handover or vote timeout changes nothing" do
      {_code, room, _dana, _timur} = host_away()

      assert_ignored(room, [
        {:timeout, make_ref(), :handover},
        {:timeout, make_ref(), :vote}
      ])
    end

    test "a vote arms its 30 seconds, and their timeout fails it for everyone" do
      {code, room, dana, timur} = host_away()

      assert Rooms.start_vote(code, "guest:dana") == :ok

      assert_receive {:forwarded, ^timur,
                      {:room_view, %{host_away: %{vote: %{yes: 1, of: 2, ends_at: 31_000}}}}}

      assert %{vote_timer: {timer, 31_000}} = :sys.get_state(room)
      assert :erlang.read_timer(timer) in 29_000..30_000

      send(room, timeout(room, :vote_timer, :vote))

      assert_receive {:forwarded, ^dana,
                      {:room_view, %{host_away: %{vote: nil, vote_again_at: 31_000}}}}

      assert %{vote_timer: nil, room: %{host_id: @host}} = :sys.get_state(room)
      assert Rooms.start_vote(code, "guest:timur") == {:error, :too_soon}
    end

    test "a yes from everyone connected hands the role over at once, and both timers stop" do
      {code, room, dana, timur} = host_away()
      :ok = Rooms.start_vote(code, "guest:dana")
      Scripted.script_seats(["guest:dana", "guest:timur"])

      assert Rooms.vote(code, "guest:timur", true) == :ok

      assert_receive {:forwarded, ^dana, {:room_view, %{host?: true, host_away: nil}}}
      assert_receive {:forwarded, ^timur, {:room_view, %{host_nickname: "Dana"}}}
      assert %{handover_timer: nil, vote_timer: nil} = :sys.get_state(room)
    end

    test "a no fails the vote, and the Host stays" do
      {code, room, _dana, timur} = host_away()
      :ok = Rooms.start_vote(code, "guest:dana")

      assert Rooms.vote(code, "guest:timur", false) == :ok

      assert_receive {:forwarded, ^timur,
                      {:room_view, %{host_away: %{vote: nil, vote_again_at: 31_000}}}}

      assert %{vote_timer: nil, room: %{host_id: @host}} = :sys.get_state(room)
    end

    test "the Host joining again cancels the handover and the vote, and they stay Host" do
      {code, room, dana, _timur} = host_away()
      :ok = Rooms.start_vote(code, "guest:dana")

      assert {:ok, %{host?: true, host_away: nil}} = Rooms.join(code, @host)

      assert_receive {:forwarded, ^dana, {:room_view, %{host_nickname: "Malika", host_away: nil}}}

      assert %{handover_timer: nil, vote_timer: nil} = :sys.get_state(room)
    end

    test "with nobody connected when the 2 minutes run out, the next to enter takes the role" do
      {:ok, code} = Rooms.create(@host, @address)
      host = join_from_another_process(code, @host)
      {:ok, _view} = Rooms.enter(code, @host, "Malika")
      room = Rooms.whereis(code)
      :sys.replace_state(room, &%{&1 | now: fn -> 1_000 end})
      leave(host)
      send(room, timeout(room, :handover_timer, :handover))

      assert %{room: %{host_id: @host}} = :sys.get_state(room)

      :sys.replace_state(room, &%{&1 | now: fn -> 200_000 end})

      assert {:ok, %{host?: true, host_away: nil}} = Rooms.enter(code, "guest:dana", "Dana")
    end

    test "a refused vote replies an error and sends nothing" do
      {code, _room, _dana, _timur} = host_away()

      assert Rooms.vote(code, "guest:dana", true) == {:error, :no_vote}
      assert Rooms.start_vote(code, "guest:aziz") == {:error, :not_member}
      :ok = Rooms.start_vote(code, "guest:dana")
      flush_views()

      assert Rooms.start_vote(code, "guest:timur") == {:error, :voting}
      assert Rooms.vote(code, "guest:dana", true) == :ok
      refute_receive {:forwarded, _pid, {:room_view, _view}}

      close(code)

      assert Rooms.start_vote(code, "guest:dana") == {:error, :closed}
      assert Rooms.vote(code, "guest:dana", true) == {:error, :closed}
    end

    test "a restored Room arms the handover and the vote again from their saved deadlines" do
      now = System.system_time(:millisecond)
      {:ok, room} = "KQXT" |> Room.new(@host) |> Room.enter(@host, "Malika")
      {:ok, room} = Room.enter(room, "guest:dana", "Dana")
      room = room |> Room.away(@host, now) |> Room.settle_handover(now, & &1)
      {:ok, room} = Room.start_vote(room, "guest:dana", now)
      room = Room.away(room, "guest:dana", now)
      Repo.insert!(%Save{code: "KQXT", room: :erlang.term_to_binary(Room.to_save(room))})

      assert Rooms.sit_out("KQXT", "guest:aziz", true) == {:error, :not_member}

      state = :sys.get_state(Rooms.whereis("KQXT"))
      handover_ends_at = now + :timer.minutes(2)
      vote_ends_at = now + :timer.seconds(30)

      assert {handover, ^handover_ends_at} = state.handover_timer
      assert {vote, ^vote_ends_at} = state.vote_timer
      assert :erlang.read_timer(handover) in :timer.seconds(110)..:timer.seconds(120)
      assert :erlang.read_timer(vote) in :timer.seconds(20)..:timer.seconds(30)
    end
  end

  test "a refused leave, removal or handover replies an error and sends nothing" do
    {code, _dana} = table()

    assert Rooms.leave(code, "guest:aziz") == {:error, :not_member}
    assert Rooms.remove(code, "guest:dana", 1) == {:error, :not_host}
    assert Rooms.remove(code, @host, 3) == {:error, :not_member}
    assert Rooms.remove(code, @host, 1) == {:error, :self}
    assert Rooms.make_host(code, "guest:dana", 2) == {:error, :not_host}
    assert Rooms.make_host(code, @host, 1) == {:error, :self}
    refute_receive {:room_view, _view}
    refute_receive {:forwarded, _pid, _message}

    close(code)

    assert Rooms.leave(code, @host) == {:error, :closed}
    assert Rooms.remove(code, @host, 2) == {:error, :closed}
    assert Rooms.make_host(code, @host, 2) == {:error, :closed}
  end

  describe "saving" do
    test "a change is written on the save tick, and nothing is written when nothing changed" do
      {:ok, code} = Rooms.create(@host, @address)
      room = Rooms.whereis(code)
      {:ok, _view} = Rooms.enter(code, @host, "Malika")

      save(room)

      assert %{members: [%{nickname: "Malika"}], host_id: @host} = saved_room(code)

      Repo.delete_all(Save)
      save(room)

      assert Repo.get(Save, code) == nil

      {:ok, _view} = Rooms.enter(code, "guest:dana", "Dana")
      save(room)

      assert %{members: [_malika, %{nickname: "Dana"}]} = saved_room(code)
    end

    test "the save never holds the Round's dice" do
      {code, _dana} = started()
      :ok = Rooms.raise(code, @host, 1, 6)

      save(Rooms.whereis(code))

      assert %{game: %{dice: dice, bid: nil, round: 1, counts: %{@host => 1}}} = saved_room(code)
      assert dice == %{}
    end

    test "a clean shutdown saves with a close deadline, and the next join brings the Room back" do
      {code, _dana} = started()
      :ok = Rooms.raise(code, @host, 1, 6)

      shut_down(code)

      assert %{closes_at: closes_at} = Repo.get(Save, code)
      assert DateTime.diff(closes_at, DateTime.utc_now(), :second) in 890..900
      assert Rooms.open?(code)

      Scripted.script([[4], [5]])

      assert {:ok, %{people: [%{nickname: "Malika"}, %{nickname: "Dana"}], game: game}} =
               Rooms.join(code, @host)

      assert %{round: 2, my_dice: [4], bid: nil, my_turn?: true} = game
    end

    test "a crash restarts the Room from its last save: the Round re-rolled, the same opener, no Bid" do
      {code, _dana} = started()
      room = Rooms.whereis(code)
      :ok = Rooms.raise(code, @host, 1, 6)
      :ok = Rooms.check(code, "guest:dana")
      send(room, {:reveal, 1, 3})
      Scripted.script([[1], [2, 2]])
      send(room, {:next_round, 1})
      :ok = Rooms.raise(code, "guest:dana", 2, 2)
      save(room)

      Scripted.script([[5], [3, 3]])
      Process.exit(room, :kill)
      restarted = restarted(code, room)

      assert {:ok, %{game: game}} = Rooms.join(code, @host)

      assert %{round: 3, my_dice: [5], bid: nil, dice_on_table: 3, turn: %{nickname: "Dana"}} =
               game

      assert %{game: %{round: 3, turn: "guest:dana"}} = :sys.get_state(restarted).room
    end

    test "a restored Room closes at the deadline it saved" do
      closes_at = DateTime.add(DateTime.utc_now(), 3, :minute)
      write_save("KQXT", closes_at)

      assert Rooms.sit_out("KQXT", "guest:aziz", true) == {:error, :not_member}

      state = :sys.get_state(Rooms.whereis("KQXT"))

      assert state.closes_at == closes_at
      assert :erlang.read_timer(state.close_timer) in :timer.minutes(2)..:timer.minutes(3)
    end

    test "the close timeout deletes the save, so the code reads closed and can be opened again" do
      :rand.seed(:exsss, {26, 26, 26})
      {:ok, code} = Rooms.create(@host, @address)
      room = Rooms.whereis(code)
      {:ok, _view} = Rooms.enter(code, @host, "Malika")
      save(room)
      ref = Process.monitor(room)

      send(room, close_timeout(room))

      assert_receive {:DOWN, ^ref, :process, ^room, :normal}
      assert Repo.get(Save, code) == nil
      refute Rooms.open?(code)
      assert Rooms.join(code, @host) == {:error, :closed}

      :rand.seed(:exsss, {26, 26, 26})
      assert Rooms.create(@host, @address) == {:ok, code}
    end

    test "a save past its close deadline, or written over 15 minutes ago with nobody gone, stays closed" do
      now = DateTime.utc_now()
      write_save("KQXT", DateTime.add(now, -1, :second))
      write_save("BCDF", nil, DateTime.add(now, -16, :minute))
      write_save("GHJK", DateTime.add(now, 1, :minute))
      write_save("LMNP", nil, DateTime.add(now, -14, :minute))

      for code <- ["KQXT", "BCDF"] do
        refute Rooms.open?(code)
        assert Rooms.join(code, @host) == {:error, :closed}
        assert Rooms.whereis(code) == nil
      end

      for code <- ["GHJK", "LMNP"] do
        assert Rooms.open?(code)
        assert {:ok, %{code: ^code, people: [%{nickname: "Malika"}]}} = Rooms.join(code, @host)
      end
    end

    test "creating skips a code with a live save, and clears a stale one" do
      :rand.seed(:exsss, {26, 26, 26})
      saved = RoomCode.random()
      write_save(saved, DateTime.add(DateTime.utc_now(), 1, :minute))

      :rand.seed(:exsss, {26, 26, 26})
      assert {:ok, code} = Rooms.create(@host, @address)
      assert code != saved

      close(code)
      write_save(code, DateTime.add(DateTime.utc_now(), -1, :minute))

      :rand.seed(:exsss, {26, 26, 26})
      assert {:ok, ^code} = Rooms.create(@host, @address)
      assert {:ok, %{people: []}} = Rooms.join(code, @host)
    end

    test "leaving, removal and handing over the Host role are each saved, a Room with no Host too" do
      {code, _dana} = table()
      room = Rooms.whereis(code)
      {:ok, _view} = Rooms.enter(code, "guest:timur", "Timur")
      save(room)

      :ok = Rooms.make_host(code, @host, 2)
      save(room)

      assert %{host_id: "guest:dana"} = saved_room(code)

      :ok = Rooms.remove(code, "guest:dana", 3)
      save(room)

      assert %{members: [_malika, _dana, %{nickname: "Timur", left?: true, removed?: true}]} =
               saved_room(code)

      :ok = Rooms.leave(code, @host)
      :ok = Rooms.leave(code, "guest:dana")
      save(room)

      assert %{host_id: nil, members: members} = saved_room(code)
      assert Enum.all?(members, & &1.left?)

      shut_down(code)

      assert {:ok, %{people: [], host?: false}} = Rooms.join(code, @host)
      assert {:ok, %{host?: true}} = Rooms.enter(code, "guest:dana", "Dana")
    end

    test "a crash after a leave voided the Round re-rolls with the voided re-roll's opener" do
      {code, _dana} = table()
      {:ok, _view} = Rooms.enter(code, "guest:timur", "Timur")
      room = Rooms.whereis(code)
      Scripted.script([[6], [2], [3]])
      :ok = Rooms.start_game(code, @host)
      Scripted.script([[4], [5]])
      :ok = Rooms.leave(code, "guest:dana")

      assert %{game: %{round: 2, turn: "guest:timur", voided_by: "guest:dana"}} =
               :sys.get_state(room).room

      save(room)
      Scripted.script([[1], [2]])
      Process.exit(room, :kill)
      restarted = restarted(code, room)

      assert {:ok, %{game: game}} = Rooms.join(code, @host)
      assert %{round: 3, my_dice: [1], voided_by: nil, turn: %{nickname: "Timur"}} = game
      assert %{game: %{turn: "guest:timur", voided_by: nil}} = :sys.get_state(restarted).room
    end

    test "a save that fails is logged, the Room carries on, and a later tick writes it" do
      {:ok, code} = Rooms.create(@host, @address)
      room = Rooms.whereis(code)
      {:ok, _view} = Rooms.enter(code, @host, "Malika")
      Repo.query!("ALTER TABLE room_saves RENAME TO room_saves_away")

      assert capture_log(fn -> save(room) end) =~ "could not write its save"

      Repo.query!("ALTER TABLE room_saves_away RENAME TO room_saves")

      assert {:ok, %{me: "Malika"}} = Rooms.join(code, @host)

      save(room)

      assert %{members: [%{nickname: "Malika"}]} = saved_room(code)
    end

    test "a save holding an atom this server has never made restores" do
      {:ok, code} = Rooms.create(@host, @address)
      {:ok, _view} = Rooms.enter(code, @host, "Malika")
      {:ok, _view} = Rooms.enter(code, "guest:dana", "Dana")
      shut_down(code)

      %{members: [malika | rest]} = saved = saved_room(code)
      member = Map.put(malika, :zq_fresh_atom_1, true)

      bin =
        %{saved | members: [member | rest]}
        |> :erlang.term_to_binary()
        |> :binary.replace("zq_fresh_atom_1", "zq_fresh_atom_9")

      assert_raise ArgumentError, fn -> String.to_existing_atom("zq_fresh_atom_9") end
      Repo.update_all(from(save in Save, where: save.code == ^code), set: [room: bin])

      assert {:ok, %{people: [%{nickname: "Malika"}, %{nickname: "Dana"}]}} =
               Rooms.join(code, @host)
    end

    test "while someone is joined, the save is written again every 5 minutes with nothing changed" do
      {code, _dana} = table()
      room = Rooms.whereis(code)
      save(room)
      age_save(code, 16)

      assert :erlang.read_timer(:sys.get_state(room).refresh_timer) in 1..:timer.minutes(5)

      send(room, refresh(room))
      :sys.get_state(room)

      assert DateTime.diff(DateTime.utc_now(), Repo.get!(Save, code).updated_at, :second) < 5
      assert :erlang.read_timer(:sys.get_state(room).refresh_timer) in 1..:timer.minutes(5)
    end

    test "a Room killed after sitting unchanged for 16 minutes is still live to the rejoin" do
      {code, _dana} = table()
      room = Rooms.whereis(code)
      save(room)
      age_save(code, 16)
      send(room, refresh(room))
      :sys.get_state(room)

      :sys.suspend(ThreeSixes.Rooms.Supervisor)
      Process.exit(room, :kill)
      wait_until_unregistered(code)

      assert Rooms.open?(code)

      :sys.resume(ThreeSixes.Rooms.Supervisor)
      restarted(code, room)

      assert {:ok, %{people: [%{nickname: "Malika"}, %{nickname: "Dana"}]}} =
               Rooms.join(code, @host)
    end

    test "a crashed Room whose save cannot be restored stays closed, and every other Room stays up" do
      supervisor = Process.whereis(ThreeSixes.Rooms.Supervisor)
      {:ok, other} = Rooms.create("guest:aziz", @address)
      {:ok, code} = Rooms.create(@host, @address)
      room = Rooms.whereis(code)
      {:ok, _view} = Rooms.enter(code, @host, "Malika")
      save(room)

      Repo.update_all(from(save in Save, where: save.code == ^code),
        set: [room: :erlang.term_to_binary("not a room")]
      )

      log =
        capture_log(fn ->
          Process.exit(room, :kill)
          settled(supervisor, room)
        end)

      assert Process.whereis(ThreeSixes.Rooms.Supervisor) == supervisor
      assert Rooms.whereis(code) == nil
      assert is_pid(Rooms.whereis(other))
      assert log =~ "could not be restored"
    end

    test "a save that cannot be read stays closed" do
      {:ok, code} = Rooms.create(@host, @address)
      {:ok, _view} = Rooms.enter(code, @host, "Malika")
      shut_down(code)
      Repo.update_all(from(save in Save, where: save.code == ^code), set: [room: "not a term"])

      assert capture_log(fn ->
               assert Rooms.join(code, @host) == {:error, :closed}
               refute Rooms.open?(code)
             end) =~ "has a save that cannot be read"

      assert Rooms.whereis(code) == nil
    end
  end

  describe "signing in" do
    @account "account:1"

    defp join_as_account(code, was) do
      test = self()

      pid =
        spawn(fn ->
          send(test, {:joined, self(), Rooms.join(code, @account, was)})
          forward(test)
        end)

      assert_receive {:joined, ^pid, reply}
      {pid, reply}
    end

    test "moves the Guest's seat to the Account and ends being Away in the same call" do
      {code, dana} = started()
      :ok = Rooms.raise(code, @host, 1, 6)
      flush_after(Rooms.whereis(code))
      leave(dana)
      assert_receive {:room_view, %{away: %{2 => _since}}}

      {_account, reply} = join_as_account(code, "guest:dana")

      assert {:moved, %{me: "Dana", game: %{my_dice: [2], my_turn?: true}}} = reply

      assert_receive {:room_view,
                      %{away: away, people: [_, %{n: 2, nickname: "Dana"}], game: game}}

      assert away == %{}
      assert %{turn: %{nickname: "Dana", n: 2}, round: 1, bid: %{count: 1}} = game
      refute_receive {:room_view, _view}

      assert Rooms.raise(code, "guest:dana", 2, 6) == {:error, :not_your_turn}
      assert Rooms.raise(code, @account, 2, 6) == :ok
    end

    test "a second join with the same marker moves nothing and sends nothing" do
      {code, _dana} = started()
      {_account, {:moved, _view}} = join_as_account(code, "guest:dana")
      flush_after(Rooms.whereis(code))

      {_again, reply} = join_as_account(code, "guest:dana")

      assert {:ok, %{me: "Dana", game: %{my_dice: [2]}}} = reply
      refute_receive {:room_view, _view}
      assert {:ok, %{me: nil}} = Rooms.join(code, "guest:dana")
    end

    test "with a seat of its own mid-bidding, the Account keeps it and the Guest's seat leaves, the Round rolled again" do
      {code, _dana} = table()
      {:ok, _view} = Rooms.enter(code, @account, "Aziz")
      {account, {:ok, _view}} = join_as_account(code, nil)
      Scripted.script([[6], [2], [3]])
      :ok = Rooms.start_game(code, @host)
      :ok = Rooms.raise(code, @host, 1, 6)
      flush_after(Rooms.whereis(code))
      Scripted.script([[4], [5]])

      {_tab, reply} = join_as_account(code, "guest:dana")

      assert {:ok, %{me: "Aziz", game: %{round: 2, my_dice: [5]}}} = reply

      assert_receive {:room_view,
                      %{people: [_, _], game: %{round: 2, my_dice: [4], voided_by: voided_by}}}

      assert voided_by.nickname == "Dana"
      assert_receive {:forwarded, ^account, {:room_view, %{game: %{round: 2, my_dice: [5]}}}}
    end

    test "with a seat of its own mid-reveal, a move that ends the Game stops that reveal's timers" do
      {code, _dana} = table()
      {:ok, _view} = Rooms.enter(code, @account, "Aziz")
      :ok = Rooms.sit_out(code, "guest:dana", true)
      room = Rooms.whereis(code)
      Scripted.script([[6], [2]])
      :ok = Rooms.start_game(code, @host)
      :ok = Rooms.raise(code, @host, 1, 6)
      :ok = Rooms.check(code, @account)

      {_tab, reply} = join_as_account(code, @host)

      assert {:ok, %{host?: true, over: %{winner: %{nickname: "Aziz", me?: true}}}} = reply

      Process.sleep(900)
      :ok = Rooms.sit_out(code, "guest:dana", false)
      Scripted.script([[6], [2]])
      :ok = Rooms.start_game(code, @account)
      :ok = Rooms.raise(code, "guest:dana", 1, 6)
      :ok = Rooms.check(code, @account)
      flush_after(room)

      refute_receive {:room_view, %{game: %{reveal: %{step: 1}}}}, 600
    end

    test "a restored Room moves the seat too, the Round rolled again" do
      {code, _dana} = started()
      shut_down(code)
      Scripted.script([[4], [5]])

      assert {:moved, view} = Rooms.join(code, @account, "guest:dana")

      assert %{me: "Dana", game: %{round: 2, my_dice: [5]}} = view
      assert Map.keys(view.away) == [1]
    end
  end

  defp save(room) do
    send(room, :save)
    :sys.get_state(room)
  end

  defp saved_room(code), do: :erlang.binary_to_term(Repo.get!(Save, code).room)

  defp write_save(code, closes_at, updated_at \\ DateTime.utc_now()) do
    {:ok, room} = code |> Room.new(@host) |> Room.enter(@host, "Malika")

    Repo.insert!(
      %Save{
        code: code,
        room: :erlang.term_to_binary(room),
        closes_at: closes_at,
        inserted_at: updated_at,
        updated_at: updated_at
      },
      on_conflict: :replace_all,
      conflict_target: :code
    )
  end

  defp age_save(code, minutes) do
    updated_at = DateTime.add(DateTime.utc_now(), -minutes, :minute)
    Repo.update_all(from(save in Save, where: save.code == ^code), set: [updated_at: updated_at])
  end

  defp refresh(room) do
    %{refresh_timer: timer} = :sys.get_state(room)
    assert is_reference(timer)
    {:timeout, timer, :refresh}
  end

  defp settled(supervisor, room) do
    busy? =
      Process.alive?(supervisor) and
        Enum.any?(DynamicSupervisor.which_children(supervisor), fn {_id, pid, _type, _modules} ->
          pid in [room, :restarting]
        end)

    if busy? do
      Process.sleep(1)
      settled(supervisor, room)
    end
  end

  defp shut_down(code) do
    :ok = DynamicSupervisor.terminate_child(ThreeSixes.Rooms.Supervisor, Rooms.whereis(code))
    wait_until_unregistered(code)
  end

  defp restarted(code, old) do
    case Rooms.whereis(code) do
      pid when is_pid(pid) and pid != old ->
        pid

      _old_or_none ->
        Process.sleep(1)
        restarted(code, old)
    end
  end

  defp assert_ignored(room, messages) do
    before = :sys.get_state(room)
    for message <- messages, do: send(room, message)
    assert :sys.get_state(room) == before
    refute_receive {:room_view, _view}
  end

  defp flush_after(room) do
    :sys.get_state(room)
    flush_views()
  end

  defp wait_for_messages(pid, count) do
    unless Process.info(pid, :message_queue_len) == {:message_queue_len, count} do
      Process.sleep(1)
      wait_for_messages(pid, count)
    end
  end

  defp close_timeout(room) do
    %{close_timer: timer} = :sys.get_state(room)
    assert is_reference(timer)
    {:timeout, timer, :close}
  end

  defp leave(pid) do
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}
  end

  defp fill_every_room do
    %{active: open} = DynamicSupervisor.count_children(ThreeSixes.Rooms.Supervisor)
    max_rooms = Application.fetch_env!(:three_sixes, :max_rooms)

    for room <- open..(max_rooms - 1)//1 do
      {:ok, code} = Rooms.create("guest:#{room}", "#{room}")
      code
    end
  end

  defp close(code) do
    pid = Rooms.whereis(code)
    :ok = GenServer.stop(pid)
    wait_until_unregistered(code)
  end

  defp wait_until_unregistered(code) do
    if Rooms.whereis(code) do
      Process.sleep(1)
      wait_until_unregistered(code)
    end
  end

  defp close_every_room do
    for {_id, pid, _type, _modules} <-
          DynamicSupervisor.which_children(ThreeSixes.Rooms.Supervisor),
        do: DynamicSupervisor.terminate_child(ThreeSixes.Rooms.Supervisor, pid)
  end

  defp open_until_exit(code) do
    pid = Rooms.whereis(code)
    on_exit(fn -> DynamicSupervisor.terminate_child(ThreeSixes.Rooms.Supervisor, pid) end)
  end
end
