defmodule ThreeSixesWeb.AwayLiveTest do
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

  describe "a Player's LiveView exiting" do
    test "makes them Away: the others see their seat greyed, with a counter from 0:00" do
      %{timur: timur, dana: dana, malika: malika, code: code} = table(~w(Timur Dana Malika))
      start(timur, [[3], [5], [2]])

      close(malika, code)

      for view <- [timur, dana] do
        assert has_element?(view, "#seat-3.is-away")
        assert text(view, "#seat-3 .seat__away") == "away 0:00"
        refute has_element?(view, "#banners")
      end

      refute has_element?(timur, "#seat-2.is-away")
      assert text(timur, "#my-page .my-page__head") == "You open. Make a Bid."
    end

    test "with the Room's clock set back 102 s reads away 1:42, and the counter runs on" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana Malika))

      :sys.replace_state(
        Rooms.whereis(code),
        &%{&1 | now: fn -> System.system_time(:millisecond) - 102_500 end}
      )

      tick_sit_out(dana, true)
      close(dana, code)

      assert has_element?(timur, "#person-2.is-away")
      assert text(timur, "#person-2 small") == "away 1:42"
      assert eventually(fn -> text(timur, "#person-2 small") == "away 1:43" end)
    end
  end

  describe "reconnecting" do
    test "gives back the same seat and dice, and nobody sees them Away any more" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana Malika))
      start(timur, [[3], [5], [2]])
      press(timur, "Bid one five")
      close(dana, code)
      assert has_element?(timur, "#seat-2.is-away")

      dana = visit(code, "dana")

      assert faces(dana) == [5]
      assert text(dana, "#my-page .my-page__head") == "Your turn. Raise it, or Check it."
      refute has_element?(dana, ".is-away")
      refute has_element?(timur, ".is-away")
      refute has_element?(timur, "#banners")
    end
  end

  describe "two tabs" do
    test "of one person both act, and closing one leaves them not Away" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))
      start(timur, [[3], [5]])
      timur_again = visit(code, "timur")

      press(timur, "Bid one five")
      press(dana, "Raise to two fives")
      check(timur_again)

      assert text(timur, "#scrap") == "You Check! 2 ×"
      assert text(dana, "#scrap") == "Timur Checks! 2 ×"

      close(timur_again, code)

      refute has_element?(dana, ".is-away")
      reveal(code, {:reveal, 1, 1})
      assert has_element?(timur, "#seat-2 .seat__dice .die.is-flip")
    end
  end

  describe "the Player on turn Away" do
    test "the table waits under a banner, and the Host removes them from it" do
      %{timur: timur, dana: dana, malika: malika, code: code} = table(~w(Timur Dana Malika))
      start(timur, [[3], [5], [2]])
      press(timur, "Bid one five")

      close(dana, code)

      assert text(timur, "#banners") ==
               "Dana is on turn and away 0:00. The table waits. Remove Dana"

      assert text(malika, "#banners") ==
               "Dana is on turn and away 0:00. The table waits. Only the Host can Remove."

      assert has_element?(timur, "#banners .banner b", "Dana")
      refute has_element?(malika, "#banners button")
      assert has_element?(timur, "#seat-2.is-away.is-turn")

      Scripted.script([[4], [6]])
      timur |> element("#banners button", "Remove Dana") |> render_click()

      for view <- [timur, malika] do
        refute has_element?(view, "#banners")
        assert has_element?(view, "#seat-2.is-out", "out")
        refute has_element?(view, "#seat-2.is-away")
      end

      assert text(timur, "#scrap") ==
               "Dana is out. The Round is voided. Malika opens the Round. 2 dice on the table"
    end

    test "during the reveal has no banner and still takes the Penalty die; the banner comes when they open" do
      %{timur: timur, dana: dana, malika: malika, code: code} = table(~w(Timur Dana Malika))
      start(timur, [[3], [5], [2]])
      press(timur, "Bid one five")
      check(dana)

      close(dana, code)
      refute has_element?(timur, "#banners")

      reveal(code, {:reveal, 1, 3})
      refute has_element?(malika, "#banners")
      assert has_element?(malika, "#seat-2.is-loser.is-away .seat__dice .die.is-penalty")

      Scripted.script([[4], [1, 6], [2]])
      reveal(code, {:next_round, 1})

      assert text(malika, "#banners") ==
               "Dana is on turn and away 0:00. The table waits. Only the Host can Remove."

      assert count(malika, "#seat-2 .seat__dice .die.is-down") == 2
    end
  end

  describe "dealing" do
    test "skips anyone Away, who watches as a Spectator when back" do
      %{timur: timur, malika: malika, code: code} = table(~w(Timur Dana Malika))

      close(malika, code)

      assert has_element?(timur, "#person-3.is-away")
      assert text(timur, "#person-3 small") == "away 0:00"

      assert text(timur, ".lobby__start .lobby__wait") ==
               "2 people are dealt in. Seats are shuffled."

      start(timur, [[3], [5]])

      refute has_element?(timur, "#seat-3")
      timur |> element("#spectators-chip") |> render_click()
      assert items(timur, "#spectators li") == ["M Malika away 0:00"]
      assert has_element?(timur, "#spectator-3.is-away")

      malika = visit(code, "malika")

      assert text(malika, "#watching") == "You're watching. Waiting for Timur."
      assert items(timur, "#spectators li") == ["M Malika"]
      refute has_element?(timur, ".is-away")
    end

    test "in the lobby, away replaces sitting out" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))
      tick_sit_out(dana, true)
      assert text(timur, "#person-2 small") == "sitting out"

      close(dana, code)

      assert text(timur, "#person-2 small") == "away 0:00"
    end
  end

  defp close(view, code) do
    GenServer.stop(view.pid)
    :sys.get_state(Rooms.whereis(code))
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
    |> String.replace("<", " <")
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.split() |> Enum.join(" ")))
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

  defp check(view), do: view |> element("#my-page button", "Check") |> render_click()

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

  defp visit(code, guest_id) do
    {:ok, view, _html} =
      build_conn() |> init_test_session(%{"guest_id" => guest_id}) |> live(~p"/r/#{code}")

    view
  end

  defp enter(view, nickname) do
    view |> form("#join-form", %{nickname: nickname}) |> render_submit()
  end
end
