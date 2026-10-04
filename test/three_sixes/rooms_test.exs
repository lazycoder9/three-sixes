defmodule ThreeSixes.RoomsTest do
  use ExUnit.Case, async: false

  alias ThreeSixes.RoomCode
  alias ThreeSixes.Rooms
  alias ThreeSixes.Rooms.Server

  @host "guest:host"

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

  defp forward(test) do
    receive do
      message -> send(test, {:forwarded, self(), message})
    end

    forward(test)
  end

  test "creating a Room opens it under its code with the creator as Host" do
    {:ok, code} = Rooms.create(@host)

    assert RoomCode.valid?(code)
    assert is_pid(Rooms.whereis(code))
    assert {:ok, %{code: ^code, host?: true, me: nil, people: []}} = Rooms.join(code, @host)
  end

  test "with every Room open, creating one is refused as busy" do
    for code <- fill_every_room(), do: open_until_exit(code)

    assert Rooms.create(@host) == {:error, :busy}
  end

  test "creating gives up as busy after ten codes that are all taken" do
    :rand.seed(:exsss, {17, 17, 17})
    taken = for _attempt <- 1..10, do: RoomCode.random()

    for code <- taken do
      DynamicSupervisor.start_child(ThreeSixes.Rooms.Supervisor, {Server, {code, @host}})
      open_until_exit(code)
    end

    :rand.seed(:exsss, {17, 17, 17})
    assert Rooms.create(@host) == {:error, :busy}
  end

  test "joining a code with no open Room is closed" do
    {:ok, code} = Rooms.create(@host)
    :ok = GenServer.stop(Rooms.whereis(code))

    assert Rooms.join(code, @host) == {:error, :closed}
    assert Rooms.join("AEIO", @host) == {:error, :closed}
  end

  test "after a person enters, every joined process gets its own view, the one who entered included" do
    {:ok, code} = Rooms.create(@host)
    {:ok, _view} = Rooms.join(code, @host)
    dana = join_from_another_process(code, "guest:dana")

    assert {:ok, %{me: "Dana", people: [%{nickname: "Dana", me?: true}]}} =
             Rooms.enter(code, "guest:dana", "Dana")

    assert_receive {:room_view,
                    %{me: nil, host?: true, people: [%{nickname: "Dana", me?: false}]}}

    assert_receive {:forwarded, ^dana, {:room_view, %{me: "Dana", host?: false}}}
  end

  test "an enter that changes nothing sends nothing" do
    {:ok, code} = Rooms.create(@host)
    {:ok, _view} = Rooms.join(code, @host)
    {:ok, _view} = Rooms.enter(code, "guest:dana", "Dana")
    assert_receive {:room_view, _view}

    assert {:ok, %{me: "Dana"}} = Rooms.enter(code, "guest:dana", "Dana")
    assert {:taken, "Dana", "Dana 2"} = Rooms.enter(code, "guest:other", "dana")
    assert {:error, :blank} = Rooms.enter(code, "guest:other", " ")
    refute_receive {:room_view, _view}
  end

  test "a process that joins twice is monitored once and gets one view per change" do
    {:ok, code} = Rooms.create(@host)
    {:ok, _view} = Rooms.join(code, @host)
    {:ok, _view} = Rooms.join(code, @host)

    assert Process.info(Rooms.whereis(code), :monitors) == {:monitors, [process: self()]}

    {:ok, _view} = Rooms.enter(code, "guest:dana", "Dana")
    assert_receive {:room_view, _view}
    refute_receive {:room_view, _view}
  end

  test "a joined process that dies is forgotten and the others still get updates" do
    {:ok, code} = Rooms.create(@host)
    {:ok, _view} = Rooms.join(code, @host)
    timur = join_from_another_process(code, "guest:timur")
    ref = Process.monitor(timur)
    Process.exit(timur, :kill)
    assert_receive {:DOWN, ^ref, :process, ^timur, :killed}

    {:ok, _view} = Rooms.enter(code, "guest:dana", "Dana")

    assert_receive {:room_view, %{people: [%{nickname: "Dana"}]}}
    assert Process.info(Rooms.whereis(code), :monitors) == {:monitors, [process: self()]}
  end

  defp fill_every_room do
    %{active: open} = DynamicSupervisor.count_children(ThreeSixes.Rooms.Supervisor)
    max_rooms = Application.fetch_env!(:three_sixes, :max_rooms)

    for _room <- open..(max_rooms - 1)//1 do
      {:ok, code} = Rooms.create(@host)
      code
    end
  end

  defp open_until_exit(code) do
    pid = Rooms.whereis(code)
    on_exit(fn -> DynamicSupervisor.terminate_child(ThreeSixes.Rooms.Supervisor, pid) end)
  end
end
