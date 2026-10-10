defmodule ThreeSixesWeb.HostAwayLiveTest do
  use ThreeSixesWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ThreeSixes.Dice.Scripted
  alias ThreeSixes.Rooms

  setup do
    on_exit(fn ->
      for {_id, pid, _type, _modules} <-
            DynamicSupervisor.which_children(ThreeSixes.Rooms.Supervisor),
          do: DynamicSupervisor.terminate_child(ThreeSixes.Rooms.Supervisor, pid)
    end)
  end

  describe "the Host Away" do
    test "in the lobby, everyone else reads how long and when the role passes on" do
      %{timur: timur, dana: dana, malika: malika, code: code} = table(~w(Timur Dana Malika))
      set_back(code, 102_500)

      close(timur, code)

      for view <- [dana, malika] do
        assert text(view, "#host-away") ==
                 "Host Timur is away 1:42. The role passes on in 0:17. Pass Host now"

        assert has_element?(view, "#host-away b", "Timur")
        refute has_element?(view, "#host-away button[disabled]")
      end
    end

    test "at the table, the banner comes after the turn-away banner" do
      %{timur: timur, dana: dana, malika: malika, code: code} = table(~w(Timur Dana Malika))
      start(timur, [[3], [5], [2]])
      set_back(code, 102_500)

      close(timur, code)

      for view <- [dana, malika] do
        assert items(view, "#banners .banner") == [
                 "Timur is on turn and away 1:42. The table waits. Only the Host can Remove.",
                 "Host Timur is away 1:42. The role passes on in 0:17. Pass Host now"
               ]
      end
    end

    test "the countdown runs on" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana Malika))
      set_back(code, 102_500)

      close(timur, code)

      assert eventually(fn ->
               text(dana, "#host-away") ==
                 "Host Timur is away 1:43. The role passes on in 0:16. Pass Host now"
             end)
    end

    test "the countdown never reads below 0:00" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana Malika))
      set_back(code, 125_500)

      close(timur, code)

      assert text(dana, "#host-away") ==
               "Host Timur is away 2:05. The role passes on in 0:00. Pass Host now"
    end
  end

  describe "the 2 minutes running out" do
    test "hand the role to someone connected, and the banner goes" do
      %{timur: timur, dana: dana, malika: malika, code: code} = table(~w(Timur Dana Malika))
      close(timur, code)
      assert has_element?(dana, "#host-away")

      Scripted.script_seats(["guest:malika", "guest:dana"])
      time_out(code, :handover)

      for view <- [dana, malika] do
        refute has_element?(view, "#host-away")
        assert has_element?(view, "#person-3 .host-tag")
        refute has_element?(view, "#person-1 .host-tag")
      end

      assert text(malika, "#flash-info p") == "You're the Host now."
      assert text(dana, "#flash-info p") == "Malika is the Host now."
      assert has_element?(malika, "#lobby button", "Start Game")
    end
  end

  describe "a vote to pass the Host role" do
    test "shows who asked, how many said yes and the time left, to each seat" do
      %{timur: timur, dana: dana, malika: malika, code: code} = table(~w(Timur Dana Malika))
      close(timur, code)
      set_back(code, 500)

      dana |> element("#host-away button", "Pass Host now") |> render_click()

      assert text(dana, "#host-away") ==
               "Pass Host now? You asked. 1 of 2 said yes. 0:29 left. You said yes."

      assert text(malika, "#host-away") ==
               "Pass Host now? Dana asked. 1 of 2 said yes. 0:29 left. Yes No"

      refute has_element?(dana, "#host-away button")
      assert has_element?(malika, "#host-away button[phx-value-yes=true]", "Yes")
      assert has_element?(malika, "#host-away button[phx-value-yes=false]", "No")
    end

    test "counts every connected person, a Spectator too, and nobody Away" do
      %{timur: timur, dana: dana, malika: malika, aziz: aziz, bobur: bobur, code: code} =
        table(~w(Timur Dana Malika Aziz Bobur))

      set_back(code, 500)
      tick_sit_out(bobur, true)
      start(timur, [[3], [5], [2], [4]])
      close(timur, code)

      dana |> element("#host-away button", "Pass Host now") |> render_click()
      bobur |> element("#host-away button", "Yes") |> render_click()

      assert text(aziz, "#host-away") ==
               "Pass Host now? Dana asked. 2 of 4 said yes. 0:29 left. Yes No"

      assert text(bobur, "#host-away") ==
               "Pass Host now? Dana asked. 2 of 4 said yes. 0:29 left. You said yes."

      close(aziz, code)

      assert text(malika, "#host-away") ==
               "Pass Host now? Dana asked. 2 of 3 said yes. 0:29 left. Yes No"
    end

    test "passes on the last yes from those connected, and the role passes at once" do
      %{timur: timur, dana: dana, malika: malika, code: code} = table(~w(Timur Dana Malika))
      close(timur, code)
      dana |> element("#host-away button", "Pass Host now") |> render_click()

      Scripted.script_seats(["guest:dana", "guest:malika"])
      malika |> element("#host-away button", "Yes") |> render_click()

      for view <- [dana, malika] do
        refute has_element?(view, "#host-away")
        assert has_element?(view, "#person-2 .host-tag")
        refute has_element?(view, "#flash-info", "The vote failed")
      end

      assert text(dana, "#flash-info p") == "You're the Host now."
      assert text(malika, "#flash-info p") == "Dana is the Host now."
    end

    test "fails on a No: the Host stays, and the banner says so in place of Pass Host now" do
      %{timur: timur, dana: dana, malika: malika, code: code} = table(~w(Timur Dana Malika))
      close(timur, code)
      dana |> element("#host-away button", "Pass Host now") |> render_click()
      set_back(code, 500)

      malika |> element("#host-away button", "No") |> render_click()

      for view <- [dana, malika] do
        assert has_element?(view, "#person-1 .host-tag")

        assert text(view, "#host-away") ==
                 "Host Timur is away 0:00. The role passes on in 1:59. The vote failed. Ask again in 0:29."

        refute has_element?(view, "#host-away button")
        refute has_element?(view, "#flash-info")
      end
    end

    test "fails when its 30 seconds run out, the same as a No" do
      %{timur: timur, dana: dana, malika: malika, code: code} = table(~w(Timur Dana Malika))
      close(timur, code)
      dana |> element("#host-away button", "Pass Host now") |> render_click()
      set_back(code, 500)

      time_out(code, :vote)

      for view <- [dana, malika] do
        assert has_element?(view, "#person-1 .host-tag")
        assert text(view, "#host-away") =~ "The vote failed. Ask again in 0:29."
        refute has_element?(view, "#host-away button")
        refute has_element?(view, "#flash-info")
      end
    end

    test "the wait counts down, and Pass Host now comes back when it ends" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana Malika))
      close(timur, code)
      dana |> element("#host-away button", "Pass Host now") |> render_click()
      set_back(code, 28_500)

      time_out(code, :vote)

      assert text(dana, "#host-away") =~ "The vote failed. Ask again in 0:01."

      assert eventually(fn ->
               has_element?(dana, "#host-away button", "Pass Host now") and
                 not (text(dana, "#host-away") =~ "The vote failed")
             end)
    end

    test "can start again once 30 seconds have passed since one failed" do
      %{timur: timur, dana: dana, malika: malika, code: code} = table(~w(Timur Dana Malika))
      close(timur, code)
      dana |> element("#host-away button", "Pass Host now") |> render_click()
      set_back(code, 30_500)

      malika |> element("#host-away button", "No") |> render_click()

      refute text(malika, "#host-away") =~ "The vote failed"
      set_back(code, 500)
      malika |> element("#host-away button", "Pass Host now") |> render_click()

      assert text(dana, "#host-away") ==
               "Pass Host now? Malika asked. 1 of 2 said yes. 0:29 left. Yes No"
    end

    test "a refused or unknown tap changes nothing" do
      %{timur: timur, dana: dana, malika: malika, code: code} = table(~w(Timur Dana Malika))
      render_hook(dana, "vote", %{"yes" => "true"})
      close(timur, code)
      set_back(code, 500)
      dana |> element("#host-away button", "Pass Host now") |> render_click()

      render_hook(malika, "vote", %{"yes" => "maybe"})
      render_hook(malika, "vote", %{})
      render_hook(dana, "vote", %{"yes" => "true"})

      assert text(malika, "#host-away") ==
               "Pass Host now? Dana asked. 1 of 2 said yes. 0:29 left. Yes No"

      refute has_element?(malika, "#flash-info")
    end
  end

  describe "two people tapping Pass Host now in the same moment" do
    test "the second tap counts as a yes in the vote the first one started" do
      %{timur: timur, dana: dana, malika: malika, code: code} =
        table(~w(Timur Dana Malika Aziz))

      close(timur, code)
      set_back(code, 500)
      dana |> element("#host-away button", "Pass Host now") |> render_click()

      render_hook(malika, "pass_host_now", %{})

      assert text(malika, "#host-away") ==
               "Pass Host now? Dana asked. 2 of 3 said yes. 0:29 left. You said yes."
    end
  end

  describe "the Host returning" do
    test "cancels the timer and the vote, and they stay Host with no message" do
      %{timur: timur, dana: dana, malika: malika, code: code} = table(~w(Timur Dana Malika))
      close(timur, code)
      dana |> element("#host-away button", "Pass Host now") |> render_click()
      %{handover_timer: {handover, _}, vote_timer: {vote, _}} = room_state(code)

      timur = visit(code, "timur")

      for view <- [timur, dana, malika] do
        refute has_element?(view, "#host-away")
        refute has_element?(view, "#banners")
        assert has_element?(view, "#person-1 .host-tag")
        refute has_element?(view, "#flash-info")
      end

      send(Rooms.whereis(code), {:timeout, handover, :handover})
      send(Rooms.whereis(code), {:timeout, vote, :vote})
      room_state(code)

      for view <- [timur, dana, malika] do
        assert has_element?(view, "#person-1 .host-tag")
        refute has_element?(view, "#flash-info")
      end

      assert has_element?(timur, "#lobby button", "Start Game")
    end
  end

  defp set_back(code, ms) do
    :sys.replace_state(
      Rooms.whereis(code),
      &%{&1 | now: fn -> System.system_time(:millisecond) - ms end}
    )
  end

  defp room_state(code), do: :sys.get_state(Rooms.whereis(code))

  defp time_out(code, timer) do
    {ref, _ends_at} = Map.fetch!(room_state(code), timer_key(timer))
    send(Rooms.whereis(code), {:timeout, ref, timer})
    room_state(code)
  end

  defp timer_key(:handover), do: :handover_timer
  defp timer_key(:vote), do: :vote_timer

  defp close(view, code) do
    GenServer.stop(view.pid)
    room_state(code)
  end

  defp eventually(check, tries \\ 40) do
    cond do
      check.() ->
        true

      tries == 0 ->
        false

      true ->
        Process.sleep(50)
        eventually(check, tries - 1)
    end
  end

  defp table(nicknames) do
    {:ok, code} = Rooms.create("guest:timur", "127.0.0.1")

    nicknames
    |> Map.new(fn nickname ->
      id = String.downcase(nickname)
      view = visit(code, id)
      enter(view, nickname)
      {String.to_existing_atom(id), view}
    end)
    |> Map.put(:code, code)
  end

  defp start(host, rolls) do
    Scripted.script(rolls)
    host |> element("#lobby button", "Start Game") |> render_click()
  end

  defp tick_sit_out(view, ticked?) do
    view |> form("#sit-out-form", %{sitting_out: to_string(ticked?)}) |> render_change()
  end

  defp items(view, selector) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.split() |> Enum.join(" ")))
  end

  defp text(view, selector) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> LazyHTML.text()
    |> String.split()
    |> Enum.join(" ")
  end

  defp visit(code, guest_id) do
    {:ok, view, _html} =
      build_conn() |> init_test_session(%{"guest_id" => guest_id}) |> live(~p"/r/#{code}")

    view
  end

  defp enter(view, nickname) do
    view |> form("#join-form", %{nickname: nickname}) |> render_submit()
  end
end
