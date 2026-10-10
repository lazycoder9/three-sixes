defmodule ThreeSixes.RoomsTest do
  use ExUnit.Case, async: false

  alias ThreeSixes.Dice.Scripted
  alias ThreeSixes.RoomCode
  alias ThreeSixes.Rooms
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
        {Server, {code, "guest:" <> code, code, []}}
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

      :ok = Rooms.raise(code, @host, round + 1, 6)
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
      :ok = Rooms.raise(code, @host, 3, 6)
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
