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
      refute has_element?(dana, "#rules-form")
      assert text(dana, "#rules") == "Game rules No turn timer"

      rules(timur, "30")

      assert has_element?(timur, "#rules-form input[name=turn_timer][value='30'][checked]")
      assert text(dana, "#rules") == "Game rules 30 s turns"

      rules(timur, "off")

      assert text(dana, "#rules") == "Game rules No turn timer"
    end

    test "a rule not on offer changes nothing and leaves the Room open" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))

      for params <- [
            %{"turn_timer" => "20"},
            %{"turn_timer" => "abc"},
            %{"turn_timer" => ["30"]},
            %{"blind_play" => "true"},
            %{}
          ],
          do: render_change(timur, "rules", params)

      render_change(dana, "rules", %{"turn_timer" => "60"})

      assert text(dana, "#rules") == "Game rules No turn timer"
      assert Rooms.whereis(code)
    end

    test "the lobby and the Room menu have no blind control" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))

      for view <- [timur, dana] do
        refute text(view, "#lobby") =~ ~r/blind|face down/i
        refute has_element?(view, "#lobby input[name=blind_play]")
        refute has_element?(view, "#blind-switch")
      end

      rules(timur, "15")
      start(timur, [[2], [6]])
      aziz = late_arrival(code)

      for view <- [timur, dana, aziz] do
        assert text(view, "#room-menu #menu-rules") == "15 s turns"
        refute text(view, "#room-menu") =~ ~r/blind/i
      end
    end
  end

  describe "the blind switch" do
    test "only a seated Player sees it, off at first, in their own band" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))
      start(timur, [[2], [6]])
      aziz = late_arrival(code)

      for player <- [timur, dana] do
        assert has_element?(
                 player,
                 ".my-band button#blind-switch[role=switch][aria-checked=false]",
                 "Play blind"
               )

        refute has_element?(player, "#blind-note")
      end

      refute has_element?(aziz, "#blind-switch")

      for junk <- [%{"blind" => "yes"}, %{"blind" => ["true"]}, %{}],
          do: render_click(timur, "blind", junk)

      assert has_element?(timur, "#blind-switch[aria-checked=false]")
      assert Rooms.whereis(code)
    end

    test "turned on mid-Round, it keeps your dice this Round and deals you the next face down, unseen by the others till your blind Bid" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))
      start(timur, [[2], [6]])

      switch(timur)

      assert has_element?(timur, "#blind-switch[aria-checked=true][aria-describedby=blind-note]")
      assert text(timur, "#blind-note") == "from the next Round"
      assert faces(timur) == [2]
      refute has_element?(timur, "#look")
      refute has_element?(dana, "#blind-note")
      refute has_element?(dana, "#blind-switch[aria-checked=true]")

      press(timur, "Bid one five")
      check(dana)
      for step <- 1..3, do: reveal(code, {:reveal, 1, step})
      next_round(code, 1, [[3, 1], [4]])

      refute_own_faces(timur)
      assert has_element?(timur, "#my-dice button#look", "Look")
      assert has_element?(timur, "#blind-switch[aria-checked=true]")
      refute has_element?(timur, "#blind-note")
      assert faces(dana) == [4]
      refute has_element?(dana, "[aria-label='three'], [aria-label='one']")
      refute has_element?(dana, ".seat__tag")
      refute has_element?(dana, "#look")

      press(timur, "Bid one five")

      assert text(dana, "#scrap") == "Timur bids blind 1 × 3 dice on the table"
      assert text(dana, "#seat-1 .seat__tag") == "blind"
      refute has_element?(dana, "[aria-label='three'], [aria-label='one']")
    end

    test "turned off during a face-down Round, the Round stays face down, and the next shows your dice" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))
      blind(code, ["timur"])
      start(timur, [[2], [6]])

      refute_own_faces(timur)
      switch(timur)

      assert has_element?(timur, "#blind-switch[aria-checked=false]")
      refute has_element?(timur, "#blind-note")
      refute_own_faces(timur)
      assert has_element?(timur, "#look")

      press(timur, "Bid one five")
      check(dana)
      for step <- 1..3, do: reveal(code, {:reveal, 1, step})
      next_round(code, 1, [[3, 1], [4]])

      assert faces(timur) == [1, 3]
      refute has_element?(timur, "#look")
    end

    test "every switched Player's dice arrive face down with Look, and no page holds a face" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))
      blind(code, ["timur", "dana"])
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
      blind(code, ["timur", "dana"])
      start(timur, [[2], [6]])
      aziz = late_arrival(code)

      press(timur, "Bid one five")

      assert text(timur, "#scrap") == "You bid blind 1 × 2 dice on the table"
      assert text(timur, ".my-band") == "Look You: 1 × blind Play blind"
      refute has_element?(timur, "#my-dice .my-dice__mark")
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
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))
      blind(code, ["timur", "dana"])
      start(timur, [[3], [5]])

      press(timur, "Bid one five")

      assert text(timur, "#my-said") == "You: 1 × blind"
      refute_own_faces(timur)

      dana |> element("#look") |> render_click()
      press(dana, "Raise to one six")

      assert text(dana, "#my-said") == "You: 1 ×"
    end

    test "a Look before Bidding shows the dice and leaves no mark" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))
      blind(code, ["timur", "dana"])
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
      %{timur: timur, dana: dana, malika: malika, code: code} = table(~w(Timur Dana Malika))
      blind(code, ["timur", "dana", "malika"])
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
      blind(code, ["timur", "dana", "malika"])
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

    test "the next Round arrives face down again while the switch stays on; with none on, dice show at once" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))
      blind(code, ["timur", "dana"])
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
      blind(code, for(n <- 1..9, do: "p#{n}"))
      start(host, List.duplicate([1], 9))
      key(host, "5")

      for player <- tl(players) do
        assert text(player, "#seat-1.seat--compact .seat__tag") == "blind"
        assert count(player, ".seat__tag") == 1
        refute_own_faces(player)
      end
    end

    test "a covered Player who leaves during a reveal shows out, with no mark" do
      %{timur: timur, dana: dana, malika: malika, code: code} = table(~w(Timur Dana Malika))
      blind(code, ["timur", "dana", "malika"])
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
      rules(timur, "30")
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
      rules(timur, "15")
      start(timur, [[2], [6]])

      time_up(code)

      assert text(timur, "#scrap") == "Time's up. You open 1 × 2 dice on the table"
      assert text(dana, "#scrap") == "Time's up. Timur opens 1 × 2 dice on the table"
      assert text(dana, "#my-page .turn-clock") == "0:15"

      time_up(code)

      assert text(timur, "#scrap") == "Time's up. Dana Checks! 1 ×"
      assert text(dana, "#scrap") == "Time's up. You Check! 1 ×"
      refute has_element?(dana, ".turn-clock")

      for step <- 1..3 do
        reveal(code, {:reveal, 1, step})

        assert text(timur, "#scrap") =~ ~r/^Time's up\. Bid 1 ×/
        assert text(dana, "#scrap") =~ ~r/^Time's up\. Bid 1 ×/
      end
    end

    test "a move by hand clears the time's up" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))
      rules(timur, "60")
      start(timur, [[2], [6]])
      time_up(code)

      press(dana, "Raise to one six")

      assert text(timur, "#scrap") == "Dana bids 1 × 2 dice on the table"
    end

    test "the Away banner and the sign-in note say the turn timer runs on" do
      %{timur: timur, dana: dana, malika: malika, code: code} = table(~w(Timur Dana Malika))
      rules(timur, "30")
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

  defp rules(view, turn_timer),
    do: view |> form("#rules-form", %{turn_timer: turn_timer}) |> render_change()

  defp blind(code, guest_ids),
    do: for(id <- guest_ids, do: :ok = Rooms.blind(code, "guest:#{id}", true))

  defp switch(view), do: view |> element("#blind-switch") |> render_click()

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
