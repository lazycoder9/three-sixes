defmodule ThreeSixesWeb.TableLiveTest do
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

  describe "the lobby" do
    test "the Host gets Start Game once two people are in, and everyone else reads who starts it" do
      {:ok, code} = Rooms.create("guest:timur", "127.0.0.1")
      dana = visit(code, "dana")
      enter(dana, "Dana")

      assert has_element?(dana, "#lobby p", "Waiting for the Host to start the Game.")

      timur = visit(code, "timur")
      enter(timur, "Timur")

      assert has_element?(timur, "#lobby button[phx-click=start]:not([disabled])", "Start Game")
      assert has_element?(timur, "#lobby p", "2 people are dealt in. Seats are shuffled.")
      assert has_element?(dana, "#lobby p", "Waiting for Timur to start the Game.")
      refute has_element?(dana, "button", "Start Game")
    end

    test "alone, the Host's Start Game is disabled: a Game needs two people" do
      {:ok, code} = Rooms.create("guest:timur", "127.0.0.1")
      timur = visit(code, "timur")
      enter(timur, "Timur")

      assert has_element?(timur, "#lobby button[disabled]", "Start Game")
      assert has_element?(timur, "#lobby p", "A Game needs two people.")
    end
  end

  describe "starting a Game" do
    test "deals both in: the table replaces the lobby, and the first seat opens the Round" do
      %{timur: timur, dana: dana} = table(~w(Timur Dana))

      start(timur, [[3], [5]])

      refute has_element?(timur, "#lobby")
      assert text(timur, "#scrap") == "You open the Round. 2 dice on the table"
      assert text(dana, "#scrap") == "Timur opens the Round. 2 dice on the table"

      assert text(timur, "#my-page .my-page__head") == "You open. Make a Bid."
      assert text(dana, "#my-page .my-page__head") == "Waiting for Timur."

      assert has_element?(dana, ".seat.is-turn[aria-current='true']", "Timur")
      assert has_element?(timur, ".seat:not(.is-turn)", "Dana")
      assert has_element?(timur, "#my-page.is-turn[aria-current='true']")
      assert has_element?(dana, ".seat .seat__dice .die.is-down")
    end
  end

  describe "the dice" do
    test "each Player sees only their own dice; the others' lie face down" do
      %{timur: timur, dana: dana} = table(~w(Timur Dana))

      start(timur, [[2], [5]])

      assert faces(timur) == [2]
      assert faces(dana) == [5]
      assert count(timur, "#my-page .cube") == 1
      assert count(dana, "#seat-1 .seat__dice .die.is-down") == 1
      refute has_element?(timur, ".seat__dice .die:not(.is-down)")
      refute has_element?(dana, ".seat__dice .die:not(.is-down)")
    end

    test "your dice roll in at Start and at a new Round, and lie still after a reload" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))
      start(timur, [[3], [5]])

      assert count(timur, "#my-page .cube.cube--tumble-in") == 1
      assert count(dana, "#my-page .cube.cube--tumble-in") == 1
      assert count(visit(code, "timur"), "#my-page .cube--tumble-in") == 0

      press(timur, "Bid one five")
      check(dana)
      for step <- 1..3, do: reveal(code, {:reveal, 1, step})
      Scripted.script([[4], [1, 6]])
      reveal(code, {:next_round, 1})

      assert count(timur, "#my-page .cube--tumble-in") == 0
      assert count(dana, "#my-page .cube") == 2
      assert count(dana, "#my-page .slot:nth-child(2) .cube.cube--tumble-in") == 1
      assert count(dana, "#my-page .cube--tumble-in") == 1
      assert count(visit(code, "dana"), "#my-page .cube--tumble-in") == 0
    end

    test "a reload mid-Round shows the same dice" do
      %{timur: timur, code: code} = table(~w(Timur Dana))
      start(timur, [[6], [3]])

      reloaded = visit(code, "timur")

      assert faces(reloaded) == [6]
      assert text(reloaded, "#my-page .my-page__head") == "You open. Make a Bid."
    end
  end

  describe "the Raises on offer" do
    test "open with every face at one die, and + and - step the count up to the dice on the table" do
      %{timur: timur} = table(~w(Timur Dana Malika))
      start(timur, [[1], [2], [3]])

      assert offers(timur) == [{"1 ×", [1, 2, 3, 4, 5, 6]}]
      assert has_element?(timur, "button[aria-label='One more']:not([disabled])")
      refute has_element?(timur, "button[aria-label='One fewer']")
      assert has_element?(timur, "button[aria-label='Bid one six']")

      press(timur, "One more")
      assert [{"2 ×", _faces}] = offers(timur)
      assert has_element?(timur, "button[aria-label='Bid two sixes']")
      assert has_element?(timur, "button[aria-label='One fewer']")

      press(timur, "One more")
      assert [{"3 ×", _faces}] = offers(timur)
      assert has_element?(timur, "button[aria-label='One more'][disabled]")

      press(timur, "One fewer")
      assert [{"2 ×", _faces}] = offers(timur)
    end

    test "after a Bid: what is left at its count, then every face at one more" do
      %{timur: timur, dana: dana, malika: malika} = table(~w(Timur Dana Malika))
      start(timur, [[1], [2], [3]])

      press(timur, "Bid one four")

      assert text(dana, "#scrap") == "Timur bids 1 × 3 dice on the table"
      assert has_element?(dana, "#scrap .bidn[aria-label='one four']")
      assert has_element?(dana, "#seat-1 .seat__said.is-now .bidn[aria-label='one four']")
      assert text(dana, "#my-page .my-page__head") == "Your turn. Raise it, or Check it."
      assert text(malika, "#my-page .my-page__head") == "Waiting for Dana."
      assert has_element?(dana, "button[aria-label='Raise to one five']")
      assert offers(dana) == [{"1 ×", [5, 6]}, {"2 ×", [1, 2, 3, 4, 5, 6]}]

      press(dana, "One more")
      press(dana, "Raise to three sixes")

      assert has_element?(malika, "#my-page .opts p", "Nothing higher is left to say.")
      refute has_element?(malika, ".pickdie")
    end

    test "the step goes back to none when the Bid changes" do
      %{timur: timur, dana: dana} = table(~w(Timur Dana Malika))
      start(timur, [[1], [2], [3]])
      press(timur, "Bid one three")

      press(dana, "One more")
      assert [_row, {"3 ×", _faces}] = offers(dana)

      press(dana, "Raise to one five")

      assert [{"1 ×", _faces}, {"2 ×", _more}] = offers(dana)
    end
  end

  describe "refusals" do
    test "only the Player on turn can act, and nothing on anyone else's page is clickable" do
      %{timur: timur, dana: dana} = table(~w(Timur Dana))
      start(timur, [[2], [5]])

      assert count(dana, "#my-page .pickdie") == 6
      assert count(dana, "#my-page button:not([disabled])") == 0

      render_click(dana, "raise", %{"count" => "1", "face" => "6"})
      render_click(dana, "check")

      assert text(timur, "#scrap") == "You open the Round. 2 dice on the table"
      assert text(timur, "#my-page .my-page__head") == "You open. Make a Bid."

      press(timur, "Bid one five")

      assert count(timur, "#my-page button:not([disabled])") == 0
      assert has_element?(dana, "#my-page button:not([disabled])", "Check")
    end

    test "the opener must Bid: their Check is disabled and refused" do
      %{timur: timur} = table(~w(Timur Dana))
      start(timur, [[2], [5]])

      assert has_element?(timur, "#my-page button[phx-click=check][disabled]", "Check")

      render_click(timur, "check")

      assert text(timur, "#scrap") == "You open the Round. 2 dice on the table"
    end

    test "an illegal Raise, or one that is not whole numbers, is refused and changes nothing" do
      %{timur: timur, dana: dana} = table(~w(Timur Dana))
      start(timur, [[2], [5]])
      press(timur, "Bid one four")

      for {count, face} <- [
            {"1", "3"},
            {"1", "4"},
            {"3", "6"},
            {"0", "6"},
            {"1", "7"},
            {"x", "5"},
            {"1.0", "5"},
            {"1abc", "5"},
            {"", ""}
          ],
          do: render_click(dana, "raise", %{"count" => count, "face" => face})

      render_click(dana, "raise", %{})
      render_click(dana, "step", %{"by" => "5"})

      assert text(dana, "#scrap") == "Timur bids 1 × 2 dice on the table"
      assert text(dana, "#my-page .my-page__head") == "Your turn. Raise it, or Check it."
      assert [{"1 ×", [5, 6]}, {"2 ×", _faces}] = offers(dana)

      press(dana, "Raise to one five")

      assert text(timur, "#scrap") == "Dana bids 1 × 2 dice on the table"
    end
  end

  describe "a full Round" do
    test "runs from Start through the Check and reveal to the next Round, opened by the loser" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))
      start(timur, [[3], [5]])
      press(timur, "Bid one five")

      check(dana)

      assert text(dana, "#scrap") == "You Check! 1 ×"
      assert text(timur, "#scrap") == "Dana Checks! 1 ×"
      assert has_element?(timur, "#scrap .bidn[aria-label='one five']")
      assert has_element?(dana, "#my-page .opts.is-hidden")
      refute has_element?(dana, "#my-page .pickdie")
      assert has_element?(dana, "#my-page button[disabled]", "Check")
      refute has_element?(timur, ".seat__dice .die:not(.is-down)")
      refute has_element?(timur, ".seat__said")
      refute has_element?(timur, ".is-turn")

      reveal(code, {:reveal, 1, 1})

      assert has_element?(timur, "#seat-2 .seat__dice .die.is-flip.is-hit")
      assert has_element?(timur, "#my-page .slot.is-miss")
      assert has_element?(dana, "#seat-1 .seat__dice .die.is-flip.is-miss")
      assert has_element?(dana, "#my-page .slot.is-hit")
      assert text(timur, "#scrap") == "Bid 1 × ? ×"
      assert has_element?(timur, "#scrap .scrap__found .bidn[aria-label='counting']")

      reveal(code, {:reveal, 1, 2})

      assert text(timur, "#scrap") == "Bid 1 × 1 × The Bid stands."

      assert has_element?(
               timur,
               "#scrap .scrap__found .bidn[aria-label='One five on the table.']"
             )

      refute has_element?(timur, ".is-loser")

      reveal(code, {:reveal, 1, 3})

      assert text(timur, "#scrap") == "Bid 1 × 1 × The Bid stands. Dana +"
      assert text(dana, "#scrap") == "Bid 1 × 1 × The Bid stands. You +"
      assert has_element?(timur, "#scrap .scrap__pen .die.is-penalty")
      assert has_element?(timur, "#seat-2.is-loser .seat__dice .die.is-penalty")
      assert count(timur, "#seat-2 .seat__dice .die") == 2
      assert has_element?(dana, "#my-page .slot--pen .die.is-penalty")
      refute has_element?(timur, "#my-page .is-penalty")

      Scripted.script([[4], [1, 6]])
      reveal(code, {:next_round, 1})

      assert faces(dana) == [1, 6]
      assert faces(timur) == [4]
      assert text(dana, "#my-page .my-page__head") == "You open. Make a Bid."
      assert text(timur, "#my-page .my-page__head") == "Waiting for Dana."
      assert text(timur, "#scrap") == "Dana opens the Round. 3 dice on the table"
      assert has_element?(timur, "#seat-2.is-turn[aria-current='true']")
      assert count(timur, "#seat-2 .seat__dice .die.is-down") == 2
      refute has_element?(timur, ".is-loser")
      refute has_element?(dana, ".is-penalty")
    end

    test "a Bluff caught: nobody holds the face, and the bidder takes the Penalty die" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))
      start(timur, [[3], [5]])
      press(timur, "Bid one six")
      check(dana)

      for step <- 1..3, do: reveal(code, {:reveal, 1, step})

      assert has_element?(dana, "#scrap .scrap__found .bidn[aria-label='Not a single six.']")
      assert text(dana, "#scrap") == "Bid 1 × 0 × Bluff caught. Timur +"
      assert has_element?(dana, "#seat-1.is-loser .die.is-penalty")
      assert has_element?(timur, "#my-page .slot--pen .die.is-penalty")
      assert count(dana, ".seat .die.is-hit") + count(dana, "#my-page .slot.is-hit") == 0

      Scripted.script([[1, 2], [3]])
      reveal(code, {:next_round, 1})

      assert text(timur, "#my-page .my-page__head") == "You open. Make a Bid."
    end
  end

  describe "Knocked out" do
    test "the Penalty die that makes six Knocks the loser out, and the next Player opens" do
      %{timur: timur, dana: dana, malika: malika, code: code} =
        players = table(~w(Timur Dana Malika))

      timur_takes_his_sixth_die(players)

      assert text(dana, "#scrap") == "Bid 1 × 0 × Bluff caught. Timur + Knocked out"
      assert text(timur, "#scrap") == "Bid 1 × 0 × Bluff caught. You + Knocked out"
      assert has_element?(dana, "#scrap .scrap__pen .red", "Knocked out")
      assert has_element?(dana, "#seat-1.is-loser:not(.is-out) .die.is-penalty")
      assert count(dana, "#seat-1 .seat__dice .die.is-flip") == 5

      next_round(code, 5, [[2], [3]])

      assert text(dana, "#my-page .my-page__head") == "You open. Make a Bid."
      assert text(malika, "#scrap") == "Dana opens the Round. 2 dice on the table"
      assert has_element?(malika, "#seat-1.is-out", "out")
      assert count(malika, "#seat-1 .die") == 0
      refute has_element?(malika, "#seat-1 .seat__said")
    end

    test "a Knocked-out Player watches: no page, their seat out, the others' dice face down" do
      %{timur: timur, dana: dana, code: code} = players = table(~w(Timur Dana Malika))
      timur_takes_his_sixth_die(players)

      assert has_element?(timur, "#my-page")

      next_round(code, 5, [[2], [3]])

      refute has_element?(timur, "#my-page")
      assert text(timur, "#watching") == "You're Knocked out. You're watching. Waiting for Dana."
      assert has_element?(timur, "#seat-1.is-out", "You")
      assert faces(timur) == []
      assert count(timur, "#seat-2 .seat__dice .die.is-down") == 1
      assert count(timur, "#seat-3 .seat__dice .die.is-down") == 1
      refute has_element?(timur, ".seat__dice .die:not(.is-down)")

      press(dana, "Bid one six")

      assert text(timur, "#watching") ==
               "You're Knocked out. You're watching. Waiting for Malika."

      refute has_element?(timur, ".seat__dice .die:not(.is-down)")
    end
  end

  describe "Game over" do
    test "a Game for three runs to Game over: the Placement, the Tally, then the Next Game" do
      %{timur: timur, dana: dana, malika: malika} = players = table(~w(Timur Dana Malika))

      play_to_game_over(players)

      refute has_element?(malika, "#game-table")
      assert text(malika, "#placement h1") == "You win!"
      assert text(dana, "#placement h1") == "Malika wins."
      assert text(dana, "#placement p") == "Final Placement, after 10 Rounds"
      assert placement(dana) == ["M Malika", "D You", "T Timur"]
      assert placement(malika) == ["M You", "D Dana", "T Timur"]
      assert has_element?(dana, "#placement li:first-child .circled", "Malika")
      assert count(dana, "#placement .circled") == 1
      assert has_element?(dana, "#placement li:nth-child(2) .hl", "You")
      assert has_element?(malika, "#placement li:first-child .circled .hl", "You")

      assert has_element?(dana, "#person-3 .tally[role=img][aria-label='1 win']")
      assert count(dana, "#person-3 .tally i") == 1
      refute has_element?(dana, "#person-1 .tally")
      refute has_element?(dana, "#person-2 .tally")

      next_game(timur, [[1], [2], [3]])

      for player <- [timur, dana, malika] do
        refute has_element?(player, "#lobby")
        assert count(player, "#my-page .cube") == 1
        assert count(player, "#my-page .cube.cube--tumble-in") == 1
        assert count(player, ".seat .seat__dice .die.is-down") == 2
        refute has_element?(player, ".seat.is-out")
      end

      assert text(dana, "#scrap") == "Timur opens the Round. 3 dice on the table"
    end

    test "the lobby page reads Next Game; the Host deals it and everyone else waits for the Host" do
      %{timur: timur, dana: dana} = players = table(~w(Timur Dana Malika))

      play_to_game_over(players)

      assert text(timur, "#lobby .paper:not(#placement) h1") == "Next Game"
      assert has_element?(timur, "#lobby button[phx-click=start]:not([disabled])", "Next Game")
      assert has_element?(timur, "#lobby p", "3 people are dealt in. Seats are shuffled.")
      refute has_element?(timur, "button", "Start Game")
      assert has_element?(dana, "#lobby p", "Waiting for Timur to start the next Game.")
      refute has_element?(dana, "#lobby button[phx-click=start]")
    end

    test "a reload at Game over shows the same Placement" do
      %{code: code} = players = table(~w(Timur Dana Malika))
      play_to_game_over(players)

      dana = visit(code, "dana")

      assert text(dana, "#placement h1") == "Malika wins."
      assert placement(dana) == ["M Malika", "D You", "T Timur"]
      assert has_element?(dana, "#person-3 .tally[aria-label='1 win']")
    end
  end

  describe "sitting out" do
    test "someone sitting out is not dealt into the next Game" do
      %{timur: timur, malika: malika} = table(~w(Timur Dana Malika))

      tick_sit_out(malika, true)
      start(timur, [[2], [5]])

      assert count(malika, ".seat") == 2
      refute has_element?(malika, ".seat", "You")
      assert count(timur, ".seat") == 1
      assert has_element?(timur, ".seat", "Dana")
      refute has_element?(malika, "#my-page")
      assert text(malika, "#watching") == "You're watching. Waiting for Timur."
    end

    test "the lobby marks who is sitting out, and the Host's count leaves them out" do
      %{timur: timur, dana: dana, malika: malika} = table(~w(Timur Dana Malika))

      tick_sit_out(malika, true)

      assert has_element?(malika, "#sit-out-form input[type=checkbox][checked]")
      refute has_element?(dana, "#sit-out-form input[type=checkbox][checked]")
      assert text(dana, "#person-3 .people__name") == "Malika sitting out"
      assert text(malika, "#person-3 .people__name") == "You sitting out"
      assert text(dana, "#person-2 .people__name") == "You"
      assert has_element?(timur, "#lobby p", "2 people are dealt in. Seats are shuffled.")

      tick_sit_out(dana, true)

      assert has_element?(timur, "#lobby button[phx-click=start][disabled]", "Start Game")
      assert has_element?(timur, "#lobby p", "A Game needs two people.")
    end

    test "unticking the box deals you in again" do
      %{timur: timur, malika: malika} = table(~w(Timur Dana Malika))

      tick_sit_out(malika, true)
      tick_sit_out(malika, false)

      refute has_element?(malika, "#sit-out-form input[type=checkbox][checked]")
      assert text(timur, "#person-3 .people__name") == "Malika"
      assert has_element?(timur, "#lobby p", "3 people are dealt in. Seats are shuffled.")

      start(timur, [[2], [5], [4]])

      assert faces(malika) == [4]
      assert count(timur, ".seat") == 2
    end

    test "the Room menu item toggles sitting out, and its words say which" do
      %{timur: timur, dana: dana, malika: malika} = table(~w(Timur Dana Malika))

      assert text(malika, "#menu-sit-out[aria-pressed=false]") == "Sit out the next Game"

      malika |> element("#menu-sit-out") |> render_click()

      assert text(malika, "#menu-sit-out[aria-pressed=true]") == "Sitting out the next Game"
      assert has_element?(malika, "#sit-out-form input[type=checkbox][checked]")
      assert text(dana, "#person-3 .people__name") == "Malika sitting out"

      malika |> element("#menu-sit-out") |> render_click()

      assert text(malika, "#menu-sit-out[aria-pressed=false]") == "Sit out the next Game"
      assert text(dana, "#person-3 .people__name") == "Malika"

      start(timur, [[2], [5], [4]])
      dana |> element("#menu-sit-out") |> render_click()

      assert text(dana, "#menu-sit-out[aria-pressed=true]") == "Sitting out the next Game"
      assert faces(dana) == [5]
    end

    test "a sit_out that is not true or false changes nothing and leaves the Room open" do
      %{timur: timur, malika: malika, code: code} = table(~w(Timur Dana Malika))

      for params <- [%{"sitting_out" => "yes"}, %{"sitting_out" => ["true"]}, %{}],
          do: render_click(malika, "sit_out", params)

      refute has_element?(malika, "#sit-out-form input[type=checkbox][checked]")
      assert has_element?(timur, "#lobby p", "3 people are dealt in. Seats are shuffled.")
      assert Rooms.whereis(code)
    end
  end

  describe "the Spectators" do
    test "a chip under the Room code counts them, and opens into a list that stays open" do
      %{dana: dana, timur: timur, code: code} = players = table(~w(Timur Dana Malika))
      timur_takes_his_sixth_die(players)

      refute has_element?(dana, "#spectators-chip")

      next_round(code, 5, [[2], [3]])

      assert text(dana, "#spectators-chip[aria-expanded=false]") == "1 Spectator"
      refute has_element?(dana, "#spectators:not([hidden])")

      aziz = visit(code, "aziz")
      enter(aziz, "Aziz")

      assert text(dana, "#spectators-chip") == "2 Spectators"
      assert text(aziz, "#spectators-chip") == "2 Spectators"

      dana |> element("#spectators-chip") |> render_click()

      assert has_element?(dana, "#spectators-chip[aria-expanded=true][aria-controls=spectators]")
      assert items(dana, "#spectators:not([hidden]) li") == ["T Timur out", "A Aziz"]
      assert has_element?(dana, "#spectators li:first-child small", "out")

      press(dana, "Bid one six")

      assert items(dana, "#spectators:not([hidden]) li") == ["T Timur out", "A Aziz"]

      timur |> element("#spectators-chip") |> render_click()

      assert items(timur, "#spectators:not([hidden]) li") == ["T You out", "A Aziz"]
      refute has_element?(aziz, "#spectators:not([hidden])")

      dana |> element("#spectators-chip") |> render_click()

      refute has_element?(dana, "#spectators:not([hidden])")
      assert has_element?(dana, "#spectators-chip[aria-expanded=false]")
    end

    test "a late arrival's HTML contains no hidden dice" do
      %{timur: timur, code: code} = table(~w(Timur Dana))
      start(timur, [[2], [5]])

      aziz = visit(code, "aziz")
      enter(aziz, "Aziz")
      html = aziz |> render() |> LazyHTML.from_fragment()

      refute has_element?(aziz, "#my-page")
      assert html |> LazyHTML.query(".cube, [data-face]") |> Enum.empty?()
      assert html |> LazyHTML.query(".die:not(.is-down)") |> Enum.count() == 1
      assert html |> LazyHTML.query(".logo .die") |> Enum.count() == 1
      assert html |> LazyHTML.query(".seat__dice .die.is-down") |> Enum.count() == 2
    end

    test "there is no chip in the lobby, nor while everyone in the Room is playing" do
      %{timur: timur, dana: dana} = table(~w(Timur Dana))

      refute has_element?(timur, "#spectators-chip")

      start(timur, [[2], [5]])

      refute has_element?(timur, "#spectators-chip")
      refute has_element?(dana, "#spectators-chip")
    end
  end

  test "someone who enters during a Game watches the table with no page and no dice" do
    %{timur: timur, code: code} = table(~w(Timur Dana))
    start(timur, [[2], [5]])
    press(timur, "Bid one five")

    aziz = visit(code, "aziz")
    enter(aziz, "Aziz")

    assert text(aziz, "#watching") == "You're watching. Waiting for Dana."
    refute has_element?(aziz, "#my-page")
    assert faces(aziz) == []
    assert count(aziz, ".seat") == 2
    refute has_element?(aziz, ".seat__dice .die:not(.is-down)")
    assert text(aziz, "#scrap") == "Timur bids 1 × 2 dice on the table"
  end

  defp timur_takes_his_sixth_die(%{timur: timur, dana: dana, code: code}) do
    start(timur, [[1], [2], [3]])

    for round <- 1..4 do
      bluff_caught(code, timur, dana, round)
      next_round(code, round, [List.duplicate(1, round + 1), [2], [3]])
    end

    bluff_caught(code, timur, dana, 5)
  end

  defp play_to_game_over(%{dana: dana, malika: malika, code: code} = players) do
    timur_takes_his_sixth_die(players)
    next_round(code, 5, [[2], [3]])

    for round <- 6..9 do
      bluff_caught(code, dana, malika, round)
      next_round(code, round, [List.duplicate(2, round - 4), [3]])
    end

    bluff_caught(code, dana, malika, 10)
    reveal(code, {:next_round, 10})
  end

  defp bluff_caught(code, bidder, checker, round) do
    press(bidder, "Bid one six")
    check(checker)
    for step <- 1..3, do: reveal(code, {:reveal, round, step})
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

  defp start(host, rolls) do
    Scripted.script(rolls)
    host |> element("#lobby button", "Start Game") |> render_click()
  end

  defp tick_sit_out(view, ticked?) do
    view |> form("#sit-out-form", %{sitting_out: to_string(ticked?)}) |> render_change()
  end

  defp next_game(host, rolls) do
    Scripted.script(rolls)
    host |> element("#lobby button", "Next Game") |> render_click()
  end

  defp placement(view), do: items(view, "#placement li")

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

  defp offers(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#my-page .orow")
    |> Enum.map(fn row ->
      faces = row |> LazyHTML.query(".pickdie") |> LazyHTML.attribute("phx-value-face")
      {row |> LazyHTML.query("b") |> LazyHTML.text(), Enum.map(faces, &String.to_integer/1)}
    end)
  end

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
