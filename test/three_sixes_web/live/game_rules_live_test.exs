defmodule ThreeSixesWeb.GameRulesLiveTest do
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

  describe "the Game rules in the lobby" do
    test "the Host sets them, and everyone else reads them" do
      %{timur: timur, dana: dana} = table(~w(Timur Dana))

      assert has_element?(timur, "#rules-form input[name=turn_timer][value=off][checked]")
      refute has_element?(timur, "#rules-form input[name=blind_play][type=checkbox][checked]")
      refute has_element?(dana, "#rules-form")
      assert text(dana, "#rules") == "Game rules No turn timer"

      rules(timur, "30", true)

      assert has_element?(timur, "#rules-form input[name=turn_timer][value='30'][checked]")
      assert has_element?(timur, "#rules-form input[name=blind_play][type=checkbox][checked]")
      assert text(dana, "#rules") == "Game rules 30 s turns · blind play"

      rules(timur, "off", true)

      assert text(dana, "#rules") == "Game rules No turn timer · blind play"
    end

    test "a rule not on offer changes nothing and leaves the Room open" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))

      for params <- [
            %{"turn_timer" => "20", "blind_play" => "true"},
            %{"turn_timer" => "abc", "blind_play" => "false"},
            %{"turn_timer" => "30", "blind_play" => "yes"},
            %{"turn_timer" => ["30"]},
            %{}
          ],
          do: render_change(timur, "rules", params)

      render_change(dana, "rules", %{"turn_timer" => "60", "blind_play" => "true"})

      assert text(dana, "#rules") == "Game rules No turn timer"
      assert Rooms.whereis(code)
    end

    test "during a Game the Room menu shows them to Players and Spectators" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))
      rules(timur, "15", true)
      start(timur, [[2], [6]])
      aziz = late_arrival(code)

      for view <- [timur, dana, aziz],
          do: assert(text(view, "#room-menu #menu-rules") == "15 s turns · blind play")

      refute has_element?(timur, "#menu-blind")
    end
  end

  describe "blind play" do
    test "every Player's dice arrive face down with Look, and no page holds a face" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))
      rules(timur, "off", true)
      start(timur, [[2], [6]])
      aziz = late_arrival(code)

      for player <- [timur, dana] do
        refute_own_faces(player)
        assert has_element?(player, "#my-dice[aria-label='Your dice, face down']")
        assert has_element?(player, "#my-dice button#look[phx-click=look]", "Look")
        refute has_element?(player, "#my-dice .my-dice__mark")
        refute has_element?(player, ".seat__tag")
      end

      assert has_element?(dana, "#my-die-1-0.die.is-down.is-rolling[aria-label='face down']")
      refute has_element?(aziz, "[data-face]")
      refute has_element?(aziz, ".seat__tag")

      refute_own_faces(visit(code, "dana"))
    end

    test "a Raise before Look is blind on every screen, and a Look after it shows peeked" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))
      rules(timur, "off", true)
      start(timur, [[2], [6]])
      aziz = late_arrival(code)

      press(timur, "Bid one five")

      assert text(timur, "#scrap") == "You bid blind 1 × 2 dice on the table"
      assert text(timur, "#my-dice .my-dice__mark") == "blind"
      refute_own_faces(timur)

      for watcher <- [dana, aziz] do
        assert text(watcher, "#scrap") == "Timur bids blind 1 × 2 dice on the table"
        assert text(watcher, "#seat-1 .seat__tag") == "blind"
      end

      timur |> element("#look") |> render_click()

      assert faces(timur) == [2]
      assert text(timur, "#my-dice .my-dice__mark") == "peeked"
      refute has_element?(timur, "#look")

      for watcher <- [dana, aziz] do
        assert text(watcher, "#seat-1 .seat__tag") == "peeked"
        refute has_element?(watcher, "[aria-label='two']")
      end

      refute_own_faces(dana)
    end

    test "your own Bid made before Look is marked blind in your band, and the next is not" do
      %{timur: timur, dana: dana} = table(~w(Timur Dana))
      rules(timur, "off", true)
      start(timur, [[3], [5]])

      press(timur, "Bid one five")

      assert text(timur, "#my-said") == "You: 1 × blind"
      refute_own_faces(timur)

      dana |> element("#look") |> render_click()
      press(dana, "Raise to one six")

      assert text(dana, "#my-said") == "You: 1 ×"
    end

    test "a Look before Bidding shows the dice and leaves no mark" do
      %{timur: timur, dana: dana} = table(~w(Timur Dana))
      rules(timur, "off", true)
      start(timur, [[2], [6]])

      timur |> element("#look") |> render_click()

      assert faces(timur) == [2]
      refute has_element?(timur, "#my-dice .my-dice__mark")
      refute has_element?(dana, ".seat__tag")

      press(timur, "Bid one five")

      assert text(dana, "#scrap") == "Timur bids 1 × 2 dice on the table"
      refute has_element?(dana, ".seat__tag")
      refute_own_faces(dana)
    end

    test "a seat's Bid made blind keeps its blind tag after a Look and the next Raise" do
      %{timur: timur, dana: dana, malika: malika} = table(~w(Timur Dana Malika))
      rules(timur, "off", true)
      start(timur, [[4], [6], [3]])

      timur |> element("#look") |> render_click()
      press(timur, "Bid one five")
      press(dana, "Raise to one six")
      dana |> element("#look") |> render_click()
      malika |> element("#look") |> render_click()
      press(malika, "Raise to two threes")

      assert text(timur, "#seat-2 .seat__said") == "1 × blind"
      assert text(timur, "#seat-2 .seat__tag") == "peeked"
      refute has_element?(timur, "#seat-3 .seat__said .seat__blind")
      refute has_element?(timur, "#seat-3 .seat__tag")
    end

    test "a covered Player on turn plays by keys, and a Check shows their dice at step 1" do
      %{timur: timur, dana: dana, malika: malika, code: code} = table(~w(Timur Dana Malika))
      rules(timur, "off", true)
      start(timur, [[4], [6], [3]])

      key(timur, "5")
      assert text(dana, "#scrap") == "Timur bids blind 1 × 3 dice on the table"

      press(dana, "Raise to one six")
      press(malika, "Raise to two sixes")
      key(timur, "c")

      refute_own_faces(timur)
      refute has_element?(timur, "#look")

      reveal(code, {:reveal, 1, 1})

      assert faces(timur) == [4]
      assert text(timur, "#my-dice .my-dice__mark") == "blind"
      assert text(dana, "#seat-1 .seat__tag") == "blind"
    end

    test "the next Round arrives face down again, and a Game without blind play shows dice at once" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))
      rules(timur, "off", true)
      start(timur, [[2], [6]])
      timur |> element("#look") |> render_click()
      press(timur, "Bid one five")
      check(dana)
      for step <- 1..3, do: reveal(code, {:reveal, 1, step})
      next_round(code, 1, [[3, 1], [4]])

      refute_own_faces(dana)
      refute_own_faces(timur)
      assert count(timur, "#my-dice > .die.is-down.is-rolling") == 2
      assert has_element?(timur, "#look")

      %{timur: plain, dana: other} = table(~w(Timur Dana))
      start(plain, [[2], [6]])

      assert faces(plain) == [2]
      assert faces(other) == [6]
      refute has_element?(plain, "#look")
    end

    test "a compact seat at a long table carries the mark too" do
      {:ok, code} = Rooms.create("guest:p1", "127.0.0.1")
      players = for n <- 1..9, do: visit(code, "p#{n}") |> tap(&enter(&1, "P#{n}"))
      host = hd(players)
      rules(host, "off", true)
      start(host, List.duplicate([1], 9))
      key(host, "5")

      for player <- tl(players) do
        assert text(player, "#seat-1.seat--compact .seat__tag") == "blind"
        assert count(player, ".seat__tag") == 1
        refute_own_faces(player)
      end
    end

    test "a covered Player who leaves during a reveal shows out, with no mark" do
      %{timur: timur, dana: dana, malika: malika} = table(~w(Timur Dana Malika))
      rules(timur, "off", true)
      start(timur, [[4], [6], [3]])

      press(timur, "Bid one five")
      press(dana, "Raise to one six")
      check(malika)
      dana |> element("#leave-dialog button", "Leave Room") |> render_click()

      assert has_element?(timur, "#seat-2.is-out .seat__out", "out")
      refute has_element?(timur, "#seat-2 .seat__tag")
    end
  end

  describe "the turn timer" do
    test "the Player on turn and every other seat see the countdown, red in its last 5 seconds" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))
      rules(timur, "30", false)
      start(timur, [[2], [6]])
      aziz = late_arrival(code)

      assert text(timur, "#my-page .turn-clock") == "0:30"
      refute has_element?(timur, ".turn-clock.is-late")
      refute has_element?(dana, "#my-page .turn-clock")

      for watcher <- [dana, aziz] do
        assert text(watcher, "#seat-1 .turn-clock") == "0:30"
        assert count(watcher, ".turn-clock") == 1
      end

      set_back(code, 26_000)
      press(timur, "Bid one five")

      assert text(dana, "#my-page .turn-clock.is-late[role=timer]") == "0:04"
      assert text(timur, "#seat-2 .turn-clock.is-late") == "0:04"
      assert text(aziz, "#seat-2 .turn-clock.is-late") == "0:04"
      refute has_element?(timur, "#my-page .turn-clock")
    end

    test "with no Bid the time-out opens with one one, then the next time-out Checks, on both seats" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))
      rules(timur, "15", false)
      start(timur, [[2], [6]])

      time_up(code)

      assert text(timur, "#scrap") == "Time's up. You open 1 × 2 dice on the table"
      assert text(dana, "#scrap") == "Time's up. Timur opens 1 × 2 dice on the table"
      assert text(dana, "#my-page .turn-clock") == "0:15"

      time_up(code)

      assert text(timur, "#scrap") == "Time's up. Dana Checks! 1 ×"
      assert text(dana, "#scrap") == "Time's up. You Check! 1 ×"
      refute has_element?(dana, ".turn-clock")

      reveal(code, {:reveal, 1, 1})

      refute text(dana, "#scrap") =~ "Time's up"
    end

    test "a move by hand clears the time's up" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))
      rules(timur, "60", false)
      start(timur, [[2], [6]])
      time_up(code)

      press(dana, "Raise to one six")

      assert text(timur, "#scrap") == "Dana bids 1 × 2 dice on the table"
    end

    test "the Away banner and the sign-in note say the turn timer runs on" do
      %{timur: timur, dana: dana, malika: malika, code: code} = table(~w(Timur Dana Malika))
      rules(timur, "30", false)
      start(timur, [[3], [5], [2]])

      assert has_element?(
               timur,
               "#menu-sign-in",
               "Your turn timer keeps running while you sign in."
             )

      refute has_element?(timur, "#menu-sign-in", "The table will wait")

      press(timur, "Bid one five")
      GenServer.stop(dana.pid)
      :sys.get_state(Rooms.whereis(code))

      assert text(malika, "#banners") ==
               "Dana is on turn and away 0:00. The turn timer runs on. Only the Host can Remove."
    end
  end

  defp rules(view, turn_timer, blind_play?) do
    view
    |> form("#rules-form", %{turn_timer: turn_timer, blind_play: to_string(blind_play?)})
    |> render_change()
  end

  defp set_back(code, ms) do
    :sys.replace_state(
      Rooms.whereis(code),
      &%{&1 | now: fn -> System.system_time(:millisecond) - ms end}
    )
  end

  defp time_up(code) do
    pid = Rooms.whereis(code)
    {timer, _clock} = :sys.get_state(pid).turn_timer
    send(pid, {:timeout, timer, :turn})
    :sys.get_state(pid)
  end

  defp next_round(code, round, rolls) do
    Scripted.script(rolls)
    reveal(code, {:next_round, round})
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
      enter(view, nickname)
      {String.to_existing_atom(id), view}
    end)
    |> Map.put(:code, code)
  end

  defp late_arrival(code) do
    aziz = visit(code, "aziz")
    enter(aziz, "Aziz")
    aziz
  end

  defp start(host, rolls) do
    Scripted.script(rolls)
    host |> element("#lobby button", "Start Game") |> render_click()
  end

  defp refute_own_faces(view) do
    html = view |> render() |> LazyHTML.from_fragment()
    band = LazyHTML.query(html, "#my-dice")
    face_word = ~r/\b(one|two|three|four|five|six)|[1-6]/i

    assert Enum.count(band) == 1
    assert html |> LazyHTML.query("[data-face]") |> Enum.empty?()
    assert band |> LazyHTML.query("i, .cube, .die *") |> Enum.empty?()
    refute LazyHTML.text(band) =~ face_word

    for label <-
          LazyHTML.attribute(LazyHTML.query(band, "[aria-label]"), "aria-label") ++
            LazyHTML.attribute(band, "aria-label"),
        do: refute(label =~ face_word)
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

  defp press(view, label),
    do: view |> element("#my-page button[aria-label='#{label}']") |> render_click()

  defp key(view, key), do: view |> element("#my-page") |> render_hook("key", %{"key" => key})

  defp check(view), do: view |> element("#my-page button", "Check") |> render_click()

  defp faces(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("[data-face]")
    |> LazyHTML.attribute("data-face")
    |> Enum.map(&String.to_integer/1)
  end

  defp count(view, selector) do
    view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.count()
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
