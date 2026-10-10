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
    test "each Player sees only their own dice, flat on the table above their page" do
      %{timur: timur, dana: dana} = table(~w(Timur Dana))

      start(timur, [[2], [5]])

      assert faces(timur) == [2]
      assert faces(dana) == [5]

      for player <- [timur, dana] do
        assert count(player, "#my-dice .die[data-face]") == 1
        assert count(player, "#my-page #my-dice, #my-page [data-face]") == 0
        assert count(player, ".cube") == 0
        refute has_element?(player, ".seat__dice .die:not(.is-down)")
      end

      assert count(dana, "#seat-1 .seat__dice .die.is-down") == 1

      assert has_element?(
               timur,
               "#my-dice[role='group'][aria-label='Your dice'] .die[role='img'][aria-label='two']"
             )

      assert has_element?(dana, "#my-dice .die[role='img'][aria-label='five']")
      refute has_element?(dana, "[aria-label='two']")
      refute has_element?(timur, "[aria-label='five']")
    end

    test "your dice roll at Start and at a new Round, and lie still after a reload" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))
      start(timur, [[3], [5]])

      assert has_element?(timur, "#my-die-1-0.die.is-rolling[data-face='3']")
      assert has_element?(dana, "#my-die-1-0.die.is-rolling[data-face='5']")
      reloaded = visit(code, "timur")
      assert count(reloaded, "#my-dice .die") == 1
      assert count(reloaded, "#my-dice .is-rolling") == 0

      press(timur, "Bid one five")
      check(dana)
      for step <- 1..3, do: reveal(code, {:reveal, 1, step})
      Scripted.script([[4], [1, 6]])
      reveal(code, {:next_round, 1})

      assert has_element?(timur, "#my-die-2-0.die.is-rolling[data-face='4']")
      assert has_element?(dana, "#my-die-2-0.die.is-rolling[data-face='1']")
      assert has_element?(dana, "#my-die-2-1.die.is-rolling[data-face='6']")
      assert count(dana, "#my-dice .die") == 2
      assert count(visit(code, "dana"), "#my-dice .is-rolling") == 0
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
    @all [1, 2, 3, 4, 5, 6]

    test "open with two rows of every face; - and + move both, up to the dice on the table" do
      %{timur: timur, dana: dana} = table(~w(Timur Dana Malika))
      start(timur, [[1], [2], [3]])

      assert offers(timur) == [{"1 ×", @all}, {"2 ×", @all}]
      assert has_element?(timur, "button[aria-label='One fewer'][disabled]")
      assert has_element?(timur, "button[aria-label='One more']:not([disabled])")
      assert has_element?(timur, "button[aria-label='Bid one six']")

      press(timur, "One more")

      assert offers(timur) == [{"2 ×", @all}, {"3 ×", @all}]
      assert has_element?(timur, "button[aria-label='Bid three sixes']")
      assert has_element?(timur, "button[aria-label='One fewer']:not([disabled])")
      assert has_element?(timur, "button[aria-label='One more'][disabled]")
      assert offers(dana) == [{"1 ×", @all}, {"2 ×", @all}]
      assert has_element?(dana, "button[aria-label='One fewer'][disabled]")
      assert has_element?(dana, "button[aria-label='One more'][disabled]")

      press(timur, "One fewer")

      assert offers(timur) == [{"1 ×", @all}, {"2 ×", @all}]
    end

    test "- and + sit in the stepped block, beside its counts, and not on the row at the Bid's count" do
      %{timur: timur, dana: dana} = table(~w(Timur Dana Malika))
      start(timur, [[1], [2], [3]])
      press(timur, "Bid one four")

      assert has_element?(dana, "#my-page .ostep button[aria-label='One fewer']")
      assert has_element?(dana, "#my-page .ostep button[aria-label='One more']")
      assert count(dana, "#my-page .ostep .orow") == 2
      refute has_element?(dana, "#my-page .orow button[phx-click=step]")
    end

    test "after a Bid: what is left at its count, then every face at one more and two more" do
      %{timur: timur, dana: dana, malika: malika} = table(~w(Timur Dana Malika))
      start(timur, [[1], [2], [3]])

      press(timur, "Bid one four")

      assert text(dana, "#scrap") == "Timur bids 1 × 3 dice on the table"
      assert has_element?(dana, "#scrap .bidn[aria-label='one four']")
      assert has_element?(dana, "#seat-1 .seat__said.is-now .bidn[aria-label='one four']")
      assert text(dana, "#my-page .my-page__head") == "Your turn. Raise it, or Check it."
      assert text(malika, "#my-page .my-page__head") == "Waiting for Dana."
      assert has_element?(dana, "button[aria-label='Raise to one five']")
      assert offers(dana) == [{"1 ×", [5, 6]}, {"2 ×", @all}, {"3 ×", @all}]
      assert has_element?(dana, "button[aria-label='One more'][disabled]")

      press(dana, "Raise to three sixes")

      assert has_element?(malika, "#my-page .opts p", "Nothing higher is left to say.")
      refute has_element?(malika, ".pickdie")
      refute has_element?(malika, "button[phx-click=step]")
    end

    test "the step goes back to none when the Bid changes" do
      %{timur: timur, dana: dana} = table(~w(Timur Dana Malika Aziz))
      start(timur, [[1], [2], [3], [4]])
      press(timur, "Bid one three")

      press(dana, "One more")
      assert [_row, {"3 ×", _faces}, {"4 ×", _more}] = offers(dana)

      press(dana, "Raise to one five")

      assert [{"1 ×", [6]}, {"2 ×", _faces}, {"3 ×", _more}] = offers(dana)
    end
  end

  describe "keyboard play" do
    test "with a Bid of 2 × ⚃, 5 Raises to 2 × ⚄" do
      %{dana: dana, malika: malika} = two_fours()

      key(dana, "5")

      assert has_element?(malika, "#scrap .bidn[aria-label='two fives']")
      assert text(malika, "#scrap") == "Dana bids 2 × 6 dice on the table"
    end

    test "with a Bid of 2 × ⚃, 2 Raises to 3 × ⚁" do
      %{dana: dana, malika: malika} = two_fours()

      key(dana, "2")

      assert has_element?(malika, "#scrap .bidn[aria-label='three twos']")
    end

    test "with a Bid of 2 × ⚃, → then 5 Raises to 4 × ⚄" do
      %{dana: dana, malika: malika} = two_fours()

      key(dana, "ArrowRight")
      assert [{"2 ×", [5, 6]}, {"4 ×", _faces}, {"5 ×", _more}] = offers(dana)
      assert [{"2 ×", [5, 6]}, {"3 ×", _faces}, {"4 ×", _more}] = offers(malika)

      key(dana, "5")

      assert has_element?(malika, "#scrap .bidn[aria-label='four fives']")
    end

    test "keys do nothing off turn: the step stays, and nothing is Raised or Checked" do
      %{timur: timur, dana: dana, malika: malika} = two_fours()
      before = offers(malika)

      for player <- [malika, timur], key <- ~w(ArrowRight + 5 1 c C), do: key(player, key)

      assert offers(malika) == before
      assert offers(timur) == before
      assert text(dana, "#scrap") == "Timur bids 2 × 6 dice on the table"
      assert text(dana, "#my-page .my-page__head") == "Your turn. Raise it, or Check it."
    end

    test "only the Player on turn's page asks for keys, and nobody's does while the reveal runs" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana))
      start(timur, [[2], [5]])

      assert has_element?(timur, "#my-page[phx-hook=PlayKeys][data-my-turn=true]")
      assert has_element?(dana, "#my-page[phx-hook=PlayKeys][data-my-turn=false]")

      press(timur, "Bid one five")

      assert has_element?(timur, "#my-page[data-my-turn=false]")
      assert has_element?(dana, "#my-page[data-my-turn=true]")

      check(dana)
      reveal(code, {:reveal, 1, 1})
      key(dana, "c")

      assert has_element?(timur, "#my-page[data-my-turn=false]")
      assert has_element?(dana, "#my-page[data-my-turn=false]")
      assert text(timur, "#scrap") == "Bid 1 × ? ×"
    end

    test "C Checks, but not when opening the Round" do
      %{timur: timur, dana: dana} = table(~w(Timur Dana))
      start(timur, [[2], [5]])

      key(timur, "c")
      assert text(dana, "#scrap") == "Timur opens the Round. 2 dice on the table"

      press(timur, "Bid one five")
      key(dana, "C")

      assert text(timur, "#scrap") == "Dana Checks! 1 ×"
    end

    test "← and -, → and + step both rows as - and + do, and stop at the ends" do
      %{dana: dana, malika: malika} = two_fours()

      key(dana, "ArrowLeft")
      assert [_row, {"3 ×", _}, {"4 ×", _}] = offers(dana)

      key(dana, "+")
      assert [_row, {"4 ×", _}, {"5 ×", _}] = offers(dana)

      for _ <- 1..3, do: key(dana, "ArrowRight")
      assert [_row, {"5 ×", _}, {"6 ×", _}] = offers(dana)
      assert has_element?(dana, "button[aria-label='One more'][disabled]")

      key(dana, "-")
      assert [_row, {"4 ×", _}, {"5 ×", _}] = offers(dana)

      key(dana, "ArrowLeft")
      assert [_row, {"3 ×", _}, {"4 ×", _}] = offers(dana)
      assert [_row, {"3 ×", _}, {"4 ×", _}] = offers(malika)
    end

    test "an unknown key or a junk payload changes nothing" do
      %{dana: dana, malika: malika} = two_fours()

      for key <- ["0", "7", "x", "=", "Enter", " ", "55", "ArrowUp"], do: key(dana, key)

      for payload <- [%{}, %{"key" => 5}, %{"key" => nil}, %{"key" => ["5"]}],
          do: dana |> element("#my-page") |> render_hook("key", payload)

      assert [{"2 ×", [5, 6]}, {"3 ×", _}, {"4 ×", _}] = offers(dana)
      assert text(malika, "#scrap") == "Timur bids 2 × 6 dice on the table"

      key(dana, "6")

      assert has_element?(malika, "#scrap .bidn[aria-label='two sixes']")
    end

    test "the Check block shows its key, on every seat's page" do
      %{timur: timur, dana: dana} = table(~w(Timur Dana))
      start(timur, [[2], [5]])

      for player <- [timur, dana] do
        assert has_element?(
                 player,
                 "#my-page button.my-page__check[aria-keyshortcuts=c] kbd[aria-hidden=true]",
                 "C"
               )
      end
    end

    test "a hint line shows the other keys, and the step keys only with room to step" do
      %{timur: timur, dana: dana, malika: malika} = table(~w(Timur Dana Malika))
      start(timur, [[2], [5], [3]])

      assert text(timur, "#my-page .keyhint") == "1 – 6 Bid · ← → fewer or more dice"
      assert text(dana, "#my-page .keyhint") == "1 – 6 Bid · ← → fewer or more dice"

      press(timur, "Bid one four")

      assert offers(dana) == [
               {"1 ×", [5, 6]},
               {"2 ×", [1, 2, 3, 4, 5, 6]},
               {"3 ×", [1, 2, 3, 4, 5, 6]}
             ]

      assert text(dana, "#my-page .keyhint") == "1 – 6 Raise"

      press(dana, "Raise to three sixes")

      refute has_element?(malika, "#my-page .keyhint")
    end

    test "two Players on one die each open with no room to step, so the hint has no step keys" do
      %{timur: timur, dana: dana} = table(~w(Timur Dana))
      start(timur, [[2], [5]])

      assert text(timur, "#my-page .keyhint") == "1 – 6 Bid"
      assert text(dana, "#my-page .keyhint") == "1 – 6 Bid"
    end

    test "the hint is dimmed with the picker off turn" do
      %{timur: timur, dana: dana} = table(~w(Timur Dana))
      start(timur, [[2], [5]])

      assert has_element?(timur, "#my-page .keyhint:not(.is-off)")
      assert has_element?(dana, "#my-page .keyhint.is-off")
    end
  end

  describe "refusals" do
    test "only the Player on turn can act, and nothing on anyone else's page is clickable" do
      %{timur: timur, dana: dana} = table(~w(Timur Dana))
      start(timur, [[2], [5]])

      assert count(dana, "#my-page .pickdie") == 12
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
      assert has_element?(timur, "#my-dice .die.is-miss[data-face='3']")
      assert has_element?(dana, "#seat-1 .seat__dice .die.is-flip.is-miss")
      assert has_element?(dana, "#my-dice .die.is-hit[data-face='5']")
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
      assert has_element?(dana, "#my-dice .die.is-penalty[role='img'][aria-label='Penalty die']")
      refute has_element?(timur, "#my-dice .is-penalty")

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
      assert has_element?(timur, "#my-dice .die.is-penalty")
      refute has_element?(dana, "#my-dice .is-penalty")
      assert count(dana, ".seat .die.is-hit") + count(dana, "#my-dice .die.is-hit") == 0
      assert has_element?(dana, "#my-dice .die.is-miss")

      Scripted.script([[1, 2], [3]])
      reveal(code, {:next_round, 1})

      assert text(timur, "#my-page .my-page__head") == "You open. Make a Bid."
    end
  end

  describe "three sixes" do
    test "a Bid of 3 × ⚅ stamps the logo onto every screen's table, out of the way of play" do
      %{timur: timur, dana: dana, malika: malika} = table(~w(Timur Dana Malika))
      start(timur, [[6], [6], [6]])
      press(timur, "One more")

      press(timur, "Bid three sixes")

      for view <- [timur, dana, malika] do
        assert has_element?(view, "#three-sixes-1.three-sixes[aria-hidden='true']")
      end

      assert has_element?(dana, "#my-page button:not([disabled])", "Check")
    end

    test "2 × ⚅ and 4 × ⚅ are ordinary Bids, and Raising past 3 × ⚅ takes the stamp away" do
      %{timur: timur, dana: dana, malika: malika} = table(~w(Timur Dana Malika Aziz))
      start(timur, [[6], [6], [6], [6]])

      press(timur, "Bid two sixes")

      refute has_element?(timur, ".three-sixes")
      refute has_element?(dana, ".three-sixes")

      press(dana, "Raise to three sixes")

      assert has_element?(timur, "#three-sixes-1")
      assert has_element?(dana, "#three-sixes-1")

      press(malika, "Raise to four sixes")

      refute has_element?(timur, ".three-sixes")
      refute has_element?(dana, ".three-sixes")
    end

    test "a Check on 3 × ⚅ costs its loser two Penalty dice, and the scrap says why" do
      %{timur: timur, dana: dana, malika: malika, code: code} = table(~w(Timur Dana Malika))
      start(timur, [[6], [6], [6]])
      press(timur, "One more")
      press(timur, "Bid three sixes")

      check(dana)

      refute has_element?(timur, ".three-sixes")
      refute has_element?(dana, ".three-sixes")

      reveal(code, {:reveal, 1, 1})
      reveal(code, {:reveal, 1, 2})

      assert text(timur, "#scrap") == "Bid 3 × 3 × The Bid stands."

      reveal(code, {:reveal, 1, 3})

      assert text(timur, "#scrap") ==
               "Bid 3 × 3 × The Bid stands. Dana +2 Three sixes counts double."

      assert text(dana, "#scrap") ==
               "Bid 3 × 3 × The Bid stands. You +2 Three sixes counts double."

      for view <- [timur, dana, malika] do
        assert count(view, "#scrap .scrap__pen .scrap__penalty .die.is-penalty") == 2
        assert has_element?(view, "#scrap .scrap__pen .scrap__penalty b", "+2")
      end

      assert count(timur, "#seat-2.is-loser .seat__dice .die.is-penalty") == 2
      assert count(malika, "#seat-2.is-loser .seat__dice .die.is-penalty") == 2
      assert count(dana, "#my-dice .die.is-penalty") == 2
      refute has_element?(timur, "#my-dice .is-penalty")
    end

    test "a Check on any other Bid costs one Penalty die, with no word of three sixes" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana Malika))
      start(timur, [[6], [2], [3]])
      press(timur, "Bid two sixes")
      check(dana)

      for step <- 1..3, do: reveal(code, {:reveal, 1, step})

      assert text(dana, "#scrap") == "Bid 2 × 1 × Bluff caught. Timur +"
      assert text(timur, "#scrap") == "Bid 2 × 1 × Bluff caught. You +"
      assert count(dana, "#scrap .scrap__pen .die.is-penalty") == 1
      assert count(dana, "#seat-1 .seat__dice .die.is-penalty") == 1
      assert count(timur, "#my-dice .die.is-penalty") == 1
    end

    test "your two Penalty dice from three sixes lie in your band after your dice, and only yours" do
      %{timur: timur, dana: dana, code: code} = table(~w(Timur Dana Malika))
      start(timur, [[6], [6], [6]])
      press(timur, "One more")
      press(timur, "Bid three sixes")
      check(dana)

      for step <- 1..3, do: reveal(code, {:reveal, 1, step})

      assert band(dana) == [{"six", false}, {"Penalty die", true}, {"Penalty die", true}]

      assert band(timur) == [{"six", false}]
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
      refute has_element?(timur, "#my-dice")
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
        assert count(player, "#my-dice .die") == 1
        assert count(player, "#my-dice .die.is-rolling") == 1
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

      sit_out = "#lobby .lobby__side #sit-out-form[phx-auto-recover=ignore]"
      assert has_element?(malika, sit_out <> " input[type=checkbox][checked]")
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

      assert text(malika, "#menu-sit-out") == "Sit out the next Game"
      refute has_element?(malika, "#menu-sit-out[aria-pressed]")

      malika |> element("#menu-sit-out") |> render_click()

      assert text(malika, "#menu-sit-out") == "Sitting out the next Game"
      assert has_element?(malika, "#sit-out-form input[type=checkbox][checked]")
      assert text(dana, "#person-3 .people__name") == "Malika sitting out"

      malika |> element("#menu-sit-out") |> render_click()

      assert text(malika, "#menu-sit-out") == "Sit out the next Game"
      assert text(dana, "#person-3 .people__name") == "Malika"

      start(timur, [[2], [5], [4]])
      dana |> element("#menu-sit-out") |> render_click()

      assert text(dana, "#menu-sit-out") == "Sitting out the next Game"
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
      %{dana: dana, timur: timur, malika: malika, code: code} =
        players = table(~w(Timur Dana Malika))

      timur_takes_his_sixth_die(players)

      assert text(dana, "#spectators-chip[aria-expanded=false]") == "1 Spectator"
      refute has_element?(dana, "#spectators:not([hidden])")

      malika |> element("#spectators-chip") |> render_click()

      assert items(malika, "#spectators:not([hidden]) li") == ["T Timur out"]

      next_round(code, 5, [[2], [3]])

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

    test "the list opened in one Game is closed when the Next Game starts" do
      %{dana: dana, timur: timur, malika: malika} = players = table(~w(Timur Dana Malika))
      timur_takes_his_sixth_die(players)
      dana |> element("#spectators-chip") |> render_click()
      play_on_to_game_over(players)

      tick_sit_out(malika, true)
      next_game(timur, [[1], [2]])

      assert text(dana, "#spectators-chip[aria-expanded=false]") == "1 Spectator"
      refute has_element?(dana, "#spectators:not([hidden])")
    end

    test "a late arrival's HTML contains no hidden dice" do
      %{timur: timur, code: code} = table(~w(Timur Dana))
      start(timur, [[2], [5]])

      aziz = visit(code, "aziz")
      enter(aziz, "Aziz")
      html = aziz |> render() |> LazyHTML.from_fragment()

      refute has_element?(aziz, "#my-page")
      refute has_element?(aziz, "#my-dice")
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

  describe "a crowded table" do
    test "up to 8 seats are full seats around a round table" do
      {_code, [host, other | _rest]} = crowd(8)

      for player <- [host, other] do
        assert count(player, ".seat") == 7
        refute has_element?(player, ".seat--compact")
        refute has_element?(player, "#game-table.game-table--long")
      end
    end

    test "past 8 seats every seat is compact, at a long table, and shows its die count" do
      {_code, [host, other | _rest]} = crowd(9)

      for player <- [host, other] do
        assert count(player, ".seat.seat--compact") == 8
        assert count(player, ".seat:not(.seat--compact)") == 0
        assert has_element?(player, "#game-table.game-table--long")
        assert items(player, ".seat .seat__n") == List.duplicate("1", 8)
        assert count(player, ".seat .seat__dice .die.is-down") >= 8
      end
    end

    test "for a phone: four others sit on an arc, and a watcher of five seats gets a ring" do
      {code, [host, other | _rest]} = crowd(5)
      aziz = late_arrival(code)

      for player <- [host, other] do
        assert has_element?(player, "#game-table.game-table--arc[data-seats='5'][data-seated]")
        refute has_element?(player, "#game-table.game-table--phone-compact")
      end

      refute has_element?(aziz, "#game-table.game-table--arc")
      refute has_element?(aziz, "#game-table.game-table--phone-compact")
      assert has_element?(aziz, "#game-table[data-seats='5']:not([data-seated])")
    end

    test "for a phone: past five seats they are compact, seated or watching" do
      {code, [host, other | _rest]} = crowd(6)
      aziz = late_arrival(code)

      for player <- [host, other, aziz] do
        assert has_element?(player, "#game-table.game-table--phone-compact[data-seats='6']")
        refute has_element?(player, "#game-table.game-table--arc")
        refute has_element?(player, "#game-table.game-table--long")
      end
    end

    test "compact seats keep the dice hidden until the reveal, then turn them over" do
      {code, players} = crowd(9)
      {opener, _n} = on_turn(players)
      press(opener, "Bid one four")
      {checker, _n} = on_turn(players)
      watcher = Enum.find(players, &(&1 not in [opener, checker]))

      for player <- [checker, watcher] do
        assert faces(player) == [1]
        refute has_element?(player, ".seat .seat__dice .die:not(.is-down)")
      end

      check(checker)
      reveal(code, {:reveal, 1, 1})

      for player <- [checker, watcher] do
        assert count(player, ".seat--compact .seat__dice .die.is-flip.is-miss") == 8
        refute has_element?(player, ".seat .seat__n")
      end
    end

    test "a compact seat shows its Bid only while it is the current Bid" do
      {_code, players} = crowd(9)
      {opener, opener_n} = on_turn(players)
      press(opener, "Bid one four")
      {raiser, raiser_n} = on_turn(players)
      press(raiser, "Raise to one five")

      for {player, n} <- Enum.with_index(players, 1), n not in [opener_n, raiser_n] do
        refute has_element?(player, "#seat-#{opener_n} .seat__said")
        assert has_element?(player, "#seat-#{raiser_n} .seat__said.is-now .bidn", "1")
      end
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

  defp play_to_game_over(players) do
    timur_takes_his_sixth_die(players)
    play_on_to_game_over(players)
  end

  defp play_on_to_game_over(%{dana: dana, malika: malika, code: code}) do
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

  defp crowd(size) do
    {:ok, code} = Rooms.create("guest:p1", "127.0.0.1")

    [host | _rest] =
      players =
      for n <- 1..size do
        view = visit(code, "p#{n}")
        enter(view, "P#{n}")
        view
      end

    start(host, List.duplicate([1], size))
    {code, players}
  end

  defp late_arrival(code) do
    aziz = visit(code, "aziz")
    enter(aziz, "Aziz")
    aziz
  end

  defp on_turn(players) do
    players
    |> Enum.with_index(1)
    |> Enum.find(fn {player, _n} -> has_element?(player, "#my-page.is-turn") end)
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

  defp two_fours do
    players = table(~w(Timur Dana Malika Aziz Bobur Cora))
    %{timur: timur, bobur: _, cora: _} = players
    start(timur, [[1], [2], [3], [4], [5], [6]])
    press(timur, "Bid two fours")
    players
  end

  defp key(view, key), do: view |> element("#my-page") |> render_hook("key", %{"key" => key})

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

  defp band(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#my-dice > .die[role='img']")
    |> Enum.map(fn die ->
      [label] = LazyHTML.attribute(die, "aria-label")
      {label, die |> LazyHTML.attribute("class") |> hd() |> String.contains?("is-penalty")}
    end)
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
