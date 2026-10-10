defmodule ThreeSixesWeb.RestoreLiveTest do
  use ThreeSixesWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ThreeSixes.Dice.Scripted
  alias ThreeSixes.Repo
  alias ThreeSixes.Room
  alias ThreeSixes.Rooms
  alias ThreeSixes.Rooms.Save

  setup do
    on_exit(fn ->
      for {_id, pid, _type, _modules} <-
            DynamicSupervisor.which_children(ThreeSixes.Rooms.Supervisor),
          do: DynamicSupervisor.terminate_child(ThreeSixes.Rooms.Supervisor, pid)
    end)
  end

  describe "restoring mid-Round" do
    test "after a crash, both seats rejoin to a re-rolled Round with the same Player opening" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))
      start(timur, [[3], [5]])
      press(timur, "Bid one five")
      press(dana, "Raise to one six")

      Scripted.script([[2], [4]])
      crash(code, 2)

      assert text(timur, "#scrap") == "You open the Round. 2 dice on the table"
      assert text(dana, "#scrap") == "Timur opens the Round. 2 dice on the table"
      refute has_element?(timur, ".seat__said")
      assert faces(timur) == [2]
      assert faces(dana) == [4]
      refute render(timur) =~ ~s(data-face="4")
      refute render(dana) =~ ~s(data-face="2")
    end

    test "a restored Round deals like any new one: the Penalty die rolls in and the steps start over" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))
      start(timur, [[3], [5]])
      press(timur, "Bid one three")
      check(dana)
      for step <- 1..3, do: reveal(code, {:reveal, 1, step})

      Scripted.script([[4], [1, 2]])
      shut_down_while_seated(code, 2)

      assert text(dana, "#scrap") == "You open the Round. 3 dice on the table"
      assert faces(dana) == [1, 2]
      assert count(dana, "#my-page .slot:nth-child(2) .cube.cube--tumble-in") == 1
      assert count(dana, "#my-page .cube--tumble-in") == 1
      assert count(timur, "#my-page .cube--tumble-in") == 0

      press(dana, "One more")
      assert offers(dana) == ["2 ×", "3 ×"]

      Scripted.script([[6], [3, 4]])
      shut_down_while_seated(code, 2)

      assert text(dana, "#scrap") == "You open the Round. 3 dice on the table"
      assert offers(dana) == ["1 ×", "2 ×"]
    end

    test "a crash back to a save from before the Round rolled starts the opener's steps over" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))
      start(timur, [[3], [5]])
      press(timur, "Bid one three")
      check(dana)
      for step <- 1..3, do: reveal(code, {:reveal, 1, step})
      reveal(code, :save)
      Scripted.script([[4], [1, 2]])
      reveal(code, {:next_round, 1})
      press(dana, "One more")

      assert offers(dana) == ["2 ×", "3 ×"]

      Scripted.script([[6], [3, 4]])
      crash_unsaved(code, 2)

      assert text(dana, "#scrap") == "You open the Round. 3 dice on the table"
      assert faces(dana) == [3, 4]
      assert offers(dana) == ["1 ×", "2 ×"]
    end

    test "after a deploy, the link still opens, and a visit brings the Room back re-rolled" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))
      start(timur, [[3], [5]])
      press(timur, "Bid one five")
      leave(code, [timur, dana])

      :ok = DynamicSupervisor.terminate_child(ThreeSixes.Rooms.Supervisor, Rooms.whereis(code))
      unregistered(code)
      refute build_conn() |> get(~p"/r/#{code}") |> html_response(200) =~ "This room has closed."

      Scripted.script([[6], [1]])
      dana = visit(code, "dana")

      assert text(dana, "#scrap") == "Timur opens the Round. 2 dice on the table"
      assert faces(dana) == [1]
      assert has_element?(dana, "#seat-1", "Timur")
      refute render(dana) =~ ~s(data-face="6")
    end

    test "after a deploy, a Player who has not come back is Away, and the table waits on them" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))
      start(timur, [[3], [5]])
      seated = :sys.get_state(Rooms.whereis(code)).room
      leave(code, [timur, dana])

      :ok = DynamicSupervisor.terminate_child(ThreeSixes.Rooms.Supervisor, Rooms.whereis(code))
      unregistered(code)
      :ok = Rooms.save(code, seated, nil)

      Scripted.script([[6], [1]])
      dana = visit(code, "dana")

      assert has_element?(dana, "#seat-1.is-away.is-turn")
      assert text(dana, "#seat-1 .seat__away") == "away 0:00"
      refute has_element?(dana, "#seat-2.is-away")

      assert text(dana, "#banners .banner:first-child") ==
               "Timur is on turn and away 0:00. The table waits. Only the Host can Remove."

      assert has_element?(dana, "#banners #host-away", "Pass Host now")
    end
  end

  describe "closing" do
    test "after 15 minutes with nobody in it, the Room closes, its link says so and its code is free" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))
      start(timur, [[3], [5]])
      leave(code, [timur, dana])
      room = Rooms.whereis(code)
      ref = Process.monitor(room)

      send(room, close_timeout(room))
      assert_receive {:DOWN, ^ref, :process, ^room, :normal}

      assert has_element?(visit(code, "dana"), "h1", "This room has closed.")
      assert Repo.get(Save, code) == nil
      refute Rooms.open?(code)
    end

    test "a save older than the 15-minute rule stays closed" do
      code = "KQXT"
      {:ok, room} = code |> Room.new("guest:timur") |> Room.enter("guest:timur", "Timur")

      Repo.insert!(%Save{
        code: code,
        room: :erlang.term_to_binary(room),
        closes_at: DateTime.add(DateTime.utc_now(), -1, :minute)
      })

      assert build_conn() |> get(~p"/r/#{code}") |> html_response(200) =~ "This room has closed."
      assert has_element?(visit(code, "timur"), "h1", "This room has closed.")
    end
  end

  defp crash(code, seats) do
    room = Rooms.whereis(code)
    send(room, :save)
    :sys.get_state(room)
    crash_unsaved(code, seats)
  end

  defp crash_unsaved(code, seats) do
    room = Rooms.whereis(code)
    ref = Process.monitor(room)
    Process.exit(room, :kill)
    assert_receive {:DOWN, ^ref, :process, ^room, :killed}
    code |> restarted(room) |> rejoined(seats)
  end

  defp shut_down_while_seated(code, seats) do
    room = Rooms.whereis(code)
    :ok = DynamicSupervisor.terminate_child(ThreeSixes.Rooms.Supervisor, room)
    code |> restarted(room) |> rejoined(seats)
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

  defp rejoined(room, seats) do
    if map_size(:sys.get_state(room).joined) < seats do
      Process.sleep(1)
      rejoined(room, seats)
    end
  end

  defp leave(code, views) do
    for view <- views do
      {_ref, _topic, proxy} = view.proxy
      GenServer.stop(proxy)
    end

    code |> Rooms.whereis() |> emptied()
  end

  defp unregistered(code) do
    if Rooms.whereis(code) do
      Process.sleep(1)
      unregistered(code)
    end
  end

  defp emptied(room) do
    if :sys.get_state(room).joined != %{} do
      Process.sleep(1)
      emptied(room)
    end
  end

  defp close_timeout(room) do
    %{close_timer: timer} = :sys.get_state(room)
    assert is_reference(timer)
    {:timeout, timer, :close}
  end

  defp reveal(code, message) do
    pid = Rooms.whereis(code)
    send(pid, message)
    :sys.get_state(pid)
  end

  defp table(nicknames) do
    {:ok, code} = Rooms.create("guest:timur", "127.0.0.1")

    nicknames
    |> Map.new(fn nickname ->
      id = String.downcase(nickname)
      view = visit(code, id)
      view |> form("#join-form", %{nickname: nickname}) |> render_submit()
      {String.to_existing_atom(id), view}
    end)
    |> Map.put(:code, code)
  end

  defp start(host, rolls) do
    Scripted.script(rolls)
    host |> element("#lobby button", "Start Game") |> render_click()
  end

  defp press(view, label),
    do: view |> element("#my-page button[aria-label='#{label}']") |> render_click()

  defp check(view), do: view |> element("#my-page button", "Check") |> render_click()

  defp visit(code, guest_id) do
    {:ok, view, _html} =
      build_conn() |> init_test_session(%{"guest_id" => guest_id}) |> live(~p"/r/#{code}")

    view
  end

  defp text(view, selector) do
    view
    |> render()
    |> String.replace("<", " <")
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> LazyHTML.text()
    |> String.split()
    |> Enum.join(" ")
  end

  defp offers(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#my-page .orow b")
    |> Enum.map(&LazyHTML.text/1)
  end

  defp faces(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#my-page [data-face]")
    |> LazyHTML.attribute("data-face")
    |> Enum.map(&String.to_integer/1)
  end

  defp count(view, selector) do
    view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.count()
  end
end
