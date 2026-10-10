defmodule ThreeSixes.GameTest do
  use ExUnit.Case, async: true

  alias ThreeSixes.Game

  @bid %{count: 3, face: 4, by: "guest:a"}

  defp round_one do
    ["a", "b", "c"]
    |> Game.new()
    |> Game.start_round(%{"a" => [2], "b" => [5], "c" => [5]})
  end

  defp check!(game, by) do
    {:ok, game} = Game.check(game, by)
    game
  end

  defp raise!(game, by, count, face) do
    {:ok, game} = Game.raise(game, by, count, face)
    game
  end

  test "with no Bid, any face from one die up to the dice on the table is legal" do
    assert Game.legal_raise?(nil, 7, 1, 1)
    assert Game.legal_raise?(nil, 7, 7, 6)
    refute Game.legal_raise?(nil, 7, 0, 3)
    refute Game.legal_raise?(nil, 7, 8, 3)
  end

  test "a higher face may keep the Bid's count; the same or a lower face needs one more" do
    assert Game.legal_raise?(@bid, 7, 3, 5)
    assert Game.legal_raise?(@bid, 7, 3, 6)
    refute Game.legal_raise?(@bid, 7, 3, 4)
    refute Game.legal_raise?(@bid, 7, 3, 1)
    assert Game.legal_raise?(@bid, 7, 4, 4)
    assert Game.legal_raise?(@bid, 7, 4, 1)
    refute Game.legal_raise?(@bid, 7, 2, 6)
  end

  test "a Raise above the dice on the table is not legal" do
    assert Game.legal_raise?(@bid, 4, 4, 2)
    refute Game.legal_raise?(@bid, 4, 5, 2)
  end

  test "faces outside one to six, and counts that are not whole numbers, are not legal" do
    refute Game.legal_raise?(nil, 7, 1, 0)
    refute Game.legal_raise?(nil, 7, 1, 7)
    refute Game.legal_raise?(nil, 7, 2.0, 3)
    refute Game.legal_raise?(nil, 7, "2", 3)
    refute Game.legal_raise?(nil, 7, 2, "3")
  end

  test "min_count is one with no Bid, the Bid's count for a higher face, one more otherwise" do
    assert Game.min_count(nil, 1) == 1
    assert Game.min_count(@bid, 5) == 3
    assert Game.min_count(@bid, 4) == 4
    assert Game.min_count(@bid, 1) == 4
  end

  describe "offers" do
    @all [1, 2, 3, 4, 5, 6]

    test "opening offers two stepped rows of every face, from one die" do
      assert Game.offers(nil, 3, 0) == [
               %{count: 1, faces: @all, stepped?: true},
               %{count: 2, faces: @all, stepped?: true}
             ]
    end

    test "a Bid offers its count with the higher faces, then two stepped rows from one more" do
      assert Game.offers(%{count: 2, face: 4}, 6, 0) == [
               %{count: 2, faces: [5, 6], stepped?: false},
               %{count: 3, faces: @all, stepped?: true},
               %{count: 4, faces: @all, stepped?: true}
             ]
    end

    test "a Bid on sixes has no row at its count" do
      assert Game.offers(%{count: 2, face: 6}, 5, 0) == [
               %{count: 3, faces: @all, stepped?: true},
               %{count: 4, faces: @all, stepped?: true}
             ]
    end

    test "a stepped row past the dice on the table is not shown" do
      assert Game.offers(%{count: 3, face: 3}, 4, 0) == [
               %{count: 3, faces: [4, 5, 6], stepped?: false},
               %{count: 4, faces: @all, stepped?: true}
             ]

      assert Game.offers(%{count: 4, face: 2}, 4, 0) == [
               %{count: 4, faces: [3, 4, 5, 6], stepped?: false}
             ]

      assert Game.offers(%{count: 4, face: 6}, 4, 0) == []
    end

    test "the step moves both stepped rows, clamped so the second stops at the dice on the table" do
      assert Game.offers(nil, 3, 1) == [
               %{count: 2, faces: @all, stepped?: true},
               %{count: 3, faces: @all, stepped?: true}
             ]

      assert [_, %{count: 6}, %{count: 7}] = Game.offers(@bid, 7, 2)
      assert [_, %{count: 6}, %{count: 7}] = Game.offers(@bid, 7, 99)
      assert [_, %{count: 4}, %{count: 5}] = Game.offers(@bid, 7, -5)
      assert [_, %{count: 4}] = Game.offers(%{count: 3, face: 3}, 4, 3)
    end

    test "max_step is how far the second stepped row can climb to the dice on the table" do
      assert Game.max_step(nil, 3) == 1
      assert Game.max_step(%{count: 2, face: 4}, 6) == 2
      assert Game.max_step(%{count: 3, face: 3}, 4) == 0
      assert Game.max_step(%{count: 4, face: 2}, 4) == 0
    end

    test "cheapest_offer is the first row on offer holding the face, or the stepped block's first row once stepped" do
      bid = %{count: 2, face: 4}

      assert Game.cheapest_offer(bid, 6, 0, 5) == {2, 5}
      assert Game.cheapest_offer(bid, 6, 0, 2) == {3, 2}
      assert Game.cheapest_offer(bid, 6, 1, 5) == {4, 5}
      assert Game.cheapest_offer(bid, 6, 1, 6) == {4, 6}
      assert Game.cheapest_offer(bid, 6, 99, 5) == {5, 5}
      assert Game.cheapest_offer(nil, 3, 0, 4) == {1, 4}
    end

    test "cheapest_offer is nil when no row on offer holds the face" do
      assert Game.cheapest_offer(%{count: 4, face: 2}, 4, 0, 1) == nil
      assert Game.cheapest_offer(%{count: 4, face: 6}, 4, 0, 6) == nil
    end

    test "every Raise on offer is legal, over every Bid on a small and a big table" do
      for dice_on_table <- [2, 5, 12],
          bid <- [
            nil | for(count <- 1..dice_on_table, face <- 1..6, do: %{count: count, face: face})
          ],
          step <- 0..dice_on_table,
          %{count: count, faces: faces} <- Game.offers(bid, dice_on_table, step),
          face <- faces do
        assert Game.legal_raise?(bid, dice_on_table, count, face),
               "#{inspect(bid)} offered #{count} x #{face} on #{dice_on_table}"
      end
    end

    test "every face key Raises to a legal offer, and finds one whenever a row holds the face" do
      for dice_on_table <- [2, 5, 12],
          bid <- [
            nil | for(count <- 1..dice_on_table, face <- 1..6, do: %{count: count, face: face})
          ],
          step <- 0..dice_on_table,
          face <- 1..6 do
        rows = Game.offers(bid, dice_on_table, step)

        case Game.cheapest_offer(bid, dice_on_table, step, face) do
          {count, ^face} ->
            assert Enum.any?(rows, &(&1.count == count and face in &1.faces))
            assert Game.legal_raise?(bid, dice_on_table, count, face)

          nil ->
            refute Enum.any?(rows, &(face in &1.faces)),
                   "#{inspect(bid)} at step #{step} found no #{face} on #{dice_on_table}"
        end
      end
    end
  end

  test "a new Game deals everyone one die, and the first seat opens Round 1" do
    game = round_one()

    assert game.counts == %{"a" => 1, "b" => 1, "c" => 1}
    assert Game.dice_on_table(game) == 3
    assert game.round == 1
    assert game.dice == %{"a" => [2], "b" => [5], "c" => [5]}
    assert game.turn == "a"
    assert game.bid == nil
    assert game.reveal == nil
  end

  describe "raise" do
    test "a Raise becomes the Bid, is what that seat said, and passes the turn on, wrapping round" do
      game = round_one() |> raise!("a", 1, 5) |> raise!("b", 1, 6)

      assert game.bid == %{count: 1, face: 6, by: "b"}
      assert game.said == %{"a" => %{count: 1, face: 5}, "b" => %{count: 1, face: 6}}
      assert game.turn == "c"

      game = raise!(game, "c", 2, 1)

      assert game.turn == "a"
      assert game.said["c"] == %{count: 2, face: 1}

      game = raise!(game, "a", 2, 3)

      assert game.said["a"] == %{count: 2, face: 3}
      assert game.turn == "b"
    end

    test "a Player not on turn cannot Raise" do
      assert Game.raise(round_one(), "b", 1, 5) == {:error, :not_your_turn}
    end

    test "a Raise that is not legal is refused" do
      game = raise!(round_one(), "a", 2, 4)

      assert Game.raise(game, "b", 2, 3) == {:error, :illegal}
      assert Game.raise(game, "b", 4, 3) == {:error, :illegal}
      assert Game.raise(game, "b", 3, 0) == {:error, :illegal}
    end
  end

  describe "check" do
    test "the opener must Bid and cannot Check" do
      assert Game.check(round_one(), "a") == {:error, :no_bid}
    end

    test "a Player not on turn cannot Check" do
      game = raise!(round_one(), "a", 1, 5)

      assert Game.check(game, "a") == {:error, :not_your_turn}
      assert Game.check(game, "c") == {:error, :not_your_turn}
    end

    test "a Bid that stands makes the Checker the loser" do
      game = round_one() |> raise!("a", 2, 5) |> check!("b")

      assert game.reveal == %{
               bid: %{count: 2, face: 5, by: "a"},
               checker: "b",
               count: 2,
               stood?: true,
               loser: "b",
               penalty: 1,
               step: 0
             }

      assert game.turn == nil
      assert game.counts == %{"a" => 1, "b" => 1, "c" => 1}
    end

    test "a Bluff caught makes the bidder the loser" do
      game = round_one() |> raise!("a", 3, 5) |> check!("b")

      assert %{count: 2, stood?: false, loser: "a", checker: "b"} = game.reveal
    end

    test "ones are not wild" do
      game =
        ["a", "b"]
        |> Game.new()
        |> Game.start_round(%{"a" => [1], "b" => [4]})
        |> raise!("a", 2, 4)
        |> check!("b")

      assert %{count: 1, stood?: false, loser: "a"} = game.reveal
    end

    test "nobody can Raise or Check during the reveal" do
      game = round_one() |> raise!("a", 2, 5) |> check!("b")

      assert Game.raise(game, "c", 3, 5) == {:error, :not_bidding}
      assert Game.raise(game, "b", 3, 5) == {:error, :not_bidding}
      assert Game.check(game, "c") == {:error, :not_bidding}
    end
  end

  describe "the reveal" do
    test "steps forward, and the loser takes the Penalty die at step 3, once" do
      game = round_one() |> raise!("a", 3, 5) |> check!("b")

      game = Game.advance_reveal(game, 1)
      assert game.reveal.step == 1
      game = Game.advance_reveal(game, 2)
      assert game.reveal.step == 2
      assert game.counts["a"] == 1

      game = Game.advance_reveal(game, 3)

      assert game.reveal.step == 3
      assert game.counts == %{"a" => 2, "b" => 1, "c" => 1}
      assert Game.dice_on_table(game) == 4
      assert Game.advance_reveal(game, 3) == game
      assert Game.advance_reveal(game, 1) == game
    end

    test "jumping straight to step 3 still gives one Penalty die" do
      game = round_one() |> raise!("a", 3, 5) |> check!("b") |> Game.advance_reveal(3)

      assert game.counts == %{"a" => 2, "b" => 1, "c" => 1}
    end

    test "with no reveal running there is nothing to advance" do
      game = raise!(round_one(), "a", 3, 5)

      assert Game.advance_reveal(game, 3) == game
    end

    test "the loser opens the next Round, rolled with their Penalty die" do
      game =
        round_one()
        |> raise!("a", 1, 2)
        |> raise!("b", 1, 5)
        |> check!("c")
        |> Game.advance_reveal(3)
        |> Game.start_round(%{"a" => [6], "b" => [1], "c" => [3, 4]})

      assert game.round == 2
      assert game.turn == "c"
      assert game.counts == %{"a" => 1, "b" => 1, "c" => 2}
      assert game.dice == %{"a" => [6], "b" => [1], "c" => [3, 4]}
      assert game.bid == nil
      assert game.said == %{}
      assert game.reveal == nil
    end
  end

  describe "the Check outcomes" do
    test "each Check is kept when its Penalty die lands, whether the Bid stood or was false" do
      game = round_one() |> raise!("a", 2, 5) |> check!("b") |> Game.advance_reveal(2)
      assert game.checks == []

      game = Game.advance_reveal(game, 3)
      stood = %{round: 1, checker: "b", bidder: "a", stood?: true}
      assert game.checks == [stood]
      assert Game.advance_reveal(game, 3) == game

      game =
        game
        |> Game.start_round(%{"a" => [2], "b" => [5, 5], "c" => [5]})
        |> raise!("b", 3, 2)
        |> check!("c")
        |> Game.advance_reveal(3)

      assert game.checks == [stood, %{round: 2, checker: "c", bidder: "b", stood?: false}]
    end

    test "a leave during the reveal still keeps the Check, at the Penalty die" do
      checked = round_one() |> raise!("a", 3, 5) |> check!("b")

      {:ok, game} = Game.leave(checked, "c")
      assert game.checks == []

      assert Game.advance_reveal(game, 3).checks == [
               %{round: 1, checker: "b", bidder: "a", stood?: false}
             ]
    end

    test "a leave that ends the Game during the reveal keeps that Check, with no Penalty die" do
      {:void, game} = Game.leave(round_one(), "c")

      checked =
        game |> Game.start_round(%{"a" => [2], "b" => [5]}) |> raise!("a", 2, 5) |> check!("b")

      for step <- 0..2 do
        game = if step == 0, do: checked, else: Game.advance_reveal(checked, step)

        assert {:over, game} = Game.leave(game, "a")
        assert game.checks == [%{round: 2, checker: "b", bidder: "a", stood?: false}]
        assert game.counts == %{"a" => 1, "b" => 1, "c" => 1}
        assert Game.placement(game) == ["b", "a", "c"]
      end
    end

    test "a leave that ends the Game after the Penalty die keeps the Check once" do
      {:void, game} = Game.leave(round_one(), "c")

      settled =
        game
        |> Game.start_round(%{"a" => [2], "b" => [5]})
        |> raise!("a", 2, 5)
        |> check!("b")
        |> Game.advance_reveal(3)

      assert {:over, game} = Game.leave(settled, "b")
      assert game.checks == [%{round: 2, checker: "b", bidder: "a", stood?: false}]
    end

    test "a Round voided before any Check keeps none" do
      {:void, game} = round_one() |> raise!("a", 1, 5) |> Game.leave("b")

      assert game.checks == []
    end
  end

  defp holding(counts, dice) do
    counts
    |> Map.keys()
    |> Enum.sort()
    |> Game.new()
    |> Map.put(:counts, counts)
    |> Game.start_round(dice)
  end

  defp lose!(game, loser, checker) do
    game
    |> raise!(loser, Game.dice_on_table(game), 6)
    |> check!(checker)
    |> Game.advance_reveal(3)
  end

  describe "Knocked out" do
    test "the sixth die Knocks its taker out at reveal step 3, once" do
      game =
        %{"a" => 5, "b" => 1, "c" => 1}
        |> holding(%{"a" => [1, 1, 1, 1, 1], "b" => [2], "c" => [3]})
        |> raise!("a", 2, 6)
        |> check!("b")
        |> Game.advance_reveal(2)

      assert game.out == []

      game = Game.advance_reveal(game, 3)

      assert game.counts["a"] == 6
      assert game.out == ["a"]
      assert Game.advance_reveal(game, 3) == game
    end

    test "a Knocked-out Player rolls no dice and has none on the table" do
      game =
        %{"a" => 5, "b" => 2, "c" => 1}
        |> holding(%{"a" => [1, 1, 1, 1, 1], "b" => [2, 2], "c" => [3]})
        |> lose!("a", "b")

      assert Game.to_roll(game) == [{"b", 2}, {"c", 1}]
      assert Game.dice_on_table(game) == 3
    end

    test "when the loser is Knocked out, the next Player in turn order opens" do
      game =
        %{"a" => 1, "b" => 5, "c" => 1}
        |> holding(%{"a" => [2], "b" => [1, 1, 1, 1, 1], "c" => [3]})
        |> raise!("a", 1, 2)
        |> lose!("b", "c")
        |> Game.start_round(%{"a" => [4], "c" => [5]})

      assert game.turn == "c"
    end

    defp a_knocked_out do
      %{"a" => 5, "b" => 1, "c" => 1, "d" => 5}
      |> holding(%{"a" => [1, 1, 1, 1, 1], "b" => [2], "c" => [3], "d" => [4, 4, 4, 4, 4]})
      |> lose!("a", "b")
      |> Game.start_round(%{"b" => [2], "c" => [3], "d" => [4, 4, 4, 4, 4]})
    end

    test "the turn passes over a Knocked-out seat, wrapping round" do
      game = a_knocked_out()
      assert game.turn == "b"

      game = game |> raise!("b", 1, 2) |> raise!("c", 1, 3) |> raise!("d", 1, 4)

      assert game.turn == "b"
    end

    test "after a Knock out, the opener is the next Player in play, past every seat out" do
      game =
        a_knocked_out()
        |> raise!("b", 1, 2)
        |> raise!("c", 1, 3)
        |> lose!("d", "b")
        |> Game.start_round(%{"b" => [5], "c" => [5]})

      assert game.out == ["a", "d"]
      assert game.turn == "b"
      assert Game.to_roll(game) == [{"b", 1}, {"c", 1}]
    end
  end

  describe "Game over" do
    test "comes when one Player is left in play" do
      game =
        %{"a" => 5, "b" => 1, "c" => 5}
        |> holding(%{"a" => [1, 1, 1, 1, 1], "b" => [2], "c" => [3, 3, 3, 3, 3]})
        |> lose!("a", "b")

      refute Game.over?(game)

      game =
        game
        |> Game.start_round(%{"b" => [2], "c" => [3, 3, 3, 3, 3]})
        |> raise!("b", 1, 2)
        |> lose!("c", "b")

      assert Game.over?(game)
    end

    test "the Placement is the winner, then the others in reverse order of being Knocked out" do
      fives = [1, 1, 1, 1, 1]

      game =
        %{"a" => 1, "b" => 5, "c" => 5, "d" => 5}
        |> holding(%{"a" => [2], "b" => fives, "c" => fives, "d" => fives})
        |> raise!("a", 1, 2)
        |> raise!("b", 1, 3)
        |> raise!("c", 1, 4)
        |> lose!("d", "a")
        |> Game.start_round(%{"a" => [2], "b" => fives, "c" => fives})
        |> raise!("a", 1, 2)
        |> lose!("b", "c")
        |> Game.start_round(%{"a" => [2], "c" => fives})
        |> lose!("c", "a")

      assert game.out == ["d", "b", "c"]
      assert Game.placement(game) == ["a", "c", "b", "d"]
    end
  end

  describe "three sixes" do
    test "is a Bid of exactly 3 × ⚅" do
      assert Game.three_sixes?(%{count: 3, face: 6})
      assert Game.three_sixes?(%{count: 3, face: 6, by: "a"})
      refute Game.three_sixes?(%{count: 2, face: 6})
      refute Game.three_sixes?(%{count: 4, face: 6})
      refute Game.three_sixes?(%{count: 3, face: 5})
      refute Game.three_sixes?(nil)
    end

    test "that stands costs the Checker two Penalty dice" do
      game =
        %{"a" => 2, "b" => 1, "c" => 1}
        |> holding(%{"a" => [6, 6], "b" => [6], "c" => [1]})
        |> raise!("a", 3, 6)
        |> check!("b")

      assert %{stood?: true, loser: "b", penalty: 2} = game.reveal

      game = Game.advance_reveal(game, 3)

      assert game.counts == %{"a" => 2, "b" => 3, "c" => 1}
      assert Game.advance_reveal(game, 3) == game
    end

    test "caught as a Bluff costs the bidder two Penalty dice" do
      game = round_one() |> raise!("a", 3, 6) |> check!("b")

      assert %{stood?: false, loser: "a", penalty: 2} = game.reveal
      assert Game.advance_reveal(game, 3).counts == %{"a" => 3, "b" => 1, "c" => 1}
    end

    test "Knocks out a Player on five dice, who ends the Game when one Player is left" do
      game =
        %{"a" => 5, "b" => 1}
        |> holding(%{"a" => [1, 1, 1, 1, 1], "b" => [2]})
        |> raise!("a", 3, 6)
        |> check!("b")
        |> Game.advance_reveal(3)

      assert game.counts["a"] == 7
      assert game.out == ["a"]
      assert Game.over?(game)
      assert Game.placement(game) == ["b", "a"]
    end

    test "Knocks out with the same Placement as one Penalty die" do
      fives = [1, 1, 1, 1, 1]

      game =
        %{"a" => 5, "b" => 1, "c" => 5}
        |> holding(%{"a" => fives, "b" => [2], "c" => fives})
        |> raise!("a", 3, 6)
        |> check!("b")
        |> Game.advance_reveal(3)

      assert game.counts["a"] == 7
      assert game.out == ["a"]
      refute Game.over?(game)
      assert Game.to_roll(game) == [{"b", 1}, {"c", 5}]

      game =
        game
        |> Game.start_round(%{"b" => [2], "c" => fives})
        |> raise!("b", 1, 2)
        |> lose!("c", "b")

      assert Game.placement(game) == ["b", "c", "a"]
    end

    test "Raised past is an ordinary Bid again: only the Checked Bid counts" do
      twos = %{"a" => 2, "b" => 2, "c" => 2}
      dice = %{"a" => [6, 6], "b" => [6, 1], "c" => [2, 3]}

      for raises <- [
            [{"a", 3, 6}, {"b", 4, 6}],
            [{"a", 3, 6}, {"b", 4, 2}],
            [{"a", 2, 6}],
            [{"a", 4, 6}]
          ] do
        game =
          Enum.reduce(raises, holding(twos, dice), fn {by, count, face}, game ->
            raise!(game, by, count, face)
          end)

        {:ok, game} = Game.check(game, game.turn)

        assert game.reveal.penalty == 1
        game = Game.advance_reveal(game, 3)
        assert Enum.sum(Map.values(game.counts)) == 7
      end
    end

    test "is kept as one Check" do
      game = round_one() |> raise!("a", 3, 6) |> check!("b") |> Game.advance_reveal(3)

      assert game.checks == [%{round: 1, checker: "b", bidder: "a", stood?: false}]
    end
  end

  describe "leaving" do
    test "while bidding Knocks the leaver out at once and voids the Round, no Penalty die taken" do
      game = round_one() |> raise!("a", 1, 5)

      assert {:void, game} = Game.leave(game, "b")

      assert game.out == ["b"]
      assert game.counts == %{"a" => 1, "b" => 1, "c" => 1}
      assert %{turn: nil, bid: nil, said: %{}, dice: %{}, reveal: nil, voided_by: "b"} = game
    end

    test "the re-rolled Round opens with the next Player in turn order after the leaver" do
      {:void, game} = round_one() |> raise!("a", 1, 5) |> Game.leave("b")
      game = Game.start_round(game, %{"a" => [3], "c" => [4]})

      assert %{round: 2, turn: "c", voided_by: "b", dice: %{"a" => [3], "c" => [4]}} = game
      assert Game.to_roll(game) == [{"a", 1}, {"c", 1}]
    end

    test "the leaver is named until the Round after the next reveal, which the loser opens" do
      {:void, game} = round_one() |> raise!("a", 1, 5) |> Game.leave("b")

      game =
        game
        |> Game.start_round(%{"a" => [3], "c" => [4]})
        |> raise!("c", 1, 4)
        |> check!("a")
        |> Game.advance_reveal(3)
        |> Game.start_round(%{"a" => [3, 3], "c" => [4]})

      assert %{turn: "a", voided_by: nil} = game
    end

    test "during the reveal leaves the Check standing: the loser still takes the Penalty die" do
      for step <- 0..2 do
        checked = round_one() |> raise!("a", 3, 5) |> check!("b")
        game = if step == 0, do: checked, else: Game.advance_reveal(checked, step)

        assert {:ok, game} = Game.leave(game, "c")
        assert %{out: ["c"], voided_by: nil, reveal: %{step: ^step, loser: "a"}} = game
        game = Game.advance_reveal(game, 3)
        assert game.counts == %{"a" => 2, "b" => 1, "c" => 1}
        assert Game.start_round(game, %{"a" => [1, 1], "b" => [1]}).turn == "a"
      end
    end

    test "by the loser during the reveal Knocks them out once, the sixth die adding no second" do
      game =
        %{"a" => 5, "b" => 1, "c" => 1}
        |> holding(%{"a" => [1, 1, 1, 1, 1], "b" => [2], "c" => [3]})
        |> raise!("a", 7, 6)
        |> check!("b")

      assert {:ok, game} = Game.leave(game, "a")
      game = Game.advance_reveal(game, 3)

      assert game.out == ["a"]
      assert Game.start_round(game, %{"b" => [1], "c" => [1]}).turn == "b"
    end

    test "by one of the last two Players during the reveal ends the Game, the other the winner" do
      {:void, game} = Game.leave(round_one(), "c")

      checked =
        game
        |> Game.start_round(%{"a" => [2], "b" => [5]})
        |> raise!("a", 2, 5)
        |> check!("b")

      assert {:over, game} = Game.leave(checked, "a")
      assert Game.placement(game) == ["b", "a", "c"]
    end

    test "once the Penalty die is taken leaves the Round settled, and the loser opens the next" do
      settled = round_one() |> raise!("a", 3, 5) |> check!("b") |> Game.advance_reveal(3)

      assert {:ok, game} = Game.leave(settled, "c")
      assert %{out: ["c"], voided_by: nil, reveal: %{step: 3, loser: "a"}} = game
      assert game.counts == %{"a" => 2, "b" => 1, "c" => 1}
      assert Game.start_round(game, %{"a" => [1, 1], "b" => [1]}).turn == "a"
    end

    test "by one of the last two Players ends the Game, the other the winner, the leaver second" do
      game =
        %{"a" => 5, "b" => 1, "c" => 1}
        |> holding(%{"a" => [1, 1, 1, 1, 1], "b" => [2], "c" => [3]})
        |> lose!("a", "b")
        |> Game.start_round(%{"b" => [2], "c" => [3]})
        |> raise!("b", 1, 2)

      assert {:over, game} = Game.leave(game, "c")
      assert Game.over?(game)
      assert Game.placement(game) == ["b", "c", "a"]
    end

    test "by the winner, in the pause after the last Knock out, ends the Game as it stood" do
      game =
        %{"a" => 5, "b" => 1}
        |> holding(%{"a" => [1, 1, 1, 1, 1], "b" => [2]})
        |> lose!("a", "b")

      assert {:over, ^game} = Game.leave(game, "b")
      assert Game.placement(game) == ["b", "a"]
    end

    test "by someone not seated, or already Knocked out, changes nothing" do
      game = raise!(a_knocked_out(), "b", 1, 2)

      assert Game.leave(game, "a") == {:ok, game}
      assert Game.leave(game, "z") == {:ok, game}
    end

    test "after the last seat leaves, the opener wraps round to the first" do
      {:void, game} = Game.leave(round_one(), "c")

      assert Game.start_round(game, %{"a" => [3], "b" => [4]}).turn == "a"
    end

    test "the opener passes over a seat already Knocked out" do
      {:void, game} = Game.leave(a_knocked_out(), "d")

      assert Game.start_round(game, %{"b" => [1], "c" => [1]}).turn == "b"
    end
  end

  describe "a Game between Rounds, as a save keeps it" do
    defp opened_by_c do
      round_one()
      |> raise!("a", 1, 2)
      |> raise!("b", 1, 5)
      |> check!("c")
      |> Game.advance_reveal(3)
      |> Game.start_round(%{"a" => [6], "b" => [1], "c" => [3, 4]})
    end

    defp assert_no_round(game) do
      assert game.dice == %{}
      assert game.bid == nil
      assert game.said == %{}
      assert game.turn == nil
      assert game.reveal == nil
    end

    test "each Round records the Player who opened it" do
      assert round_one().opener == "a"
      assert opened_by_c().opener == "c"
    end

    test "while bidding, the Round is void, and the re-roll is the next Round with the same opener" do
      game = opened_by_c() |> raise!("c", 1, 3) |> raise!("a", 2, 3)

      between = Game.without_round(game)

      assert_no_round(between)
      assert %{round: 2, opener: "c"} = between
      assert between.counts == game.counts

      game = Game.start_round(between, %{"a" => [1], "b" => [2], "c" => [3, 3]})

      assert game.round == 3
      assert game.turn == "c"
    end

    test "during the reveal before the Penalty die, the Round is void and nobody takes a die" do
      for step <- 0..2 do
        between =
          opened_by_c()
          |> raise!("c", 1, 3)
          |> check!("a")
          |> Game.advance_reveal(step)
          |> Game.without_round()

        assert_no_round(between)
        assert between.counts == opened_by_c().counts
        assert between.opener == "c"
        assert Game.start_round(between, %{"a" => [1], "b" => [2], "c" => [3, 3]}).turn == "c"
      end
    end

    test "once the Penalty die is taken it stays, and the loser opens the next Round" do
      between =
        opened_by_c()
        |> raise!("c", 1, 3)
        |> check!("a")
        |> Game.advance_reveal(3)
        |> Game.without_round()

      assert_no_round(between)
      assert between.counts == %{"a" => 2, "b" => 1, "c" => 2}
      assert between.opener == "a"

      game = Game.start_round(between, %{"a" => [1, 1], "b" => [2], "c" => [3, 3]})

      assert game.round == 3
      assert game.turn == "a"
    end

    test "a loser Knocked out by the Penalty die hands the opening to the next Player in play" do
      between =
        %{"a" => 1, "b" => 5, "c" => 1}
        |> holding(%{"a" => [2], "b" => [1, 1, 1, 1, 1], "c" => [3]})
        |> raise!("a", 1, 2)
        |> lose!("b", "c")
        |> Game.without_round()

      assert %{opener: "c", out: ["b"]} = between
      assert Game.start_round(between, %{"a" => [4], "c" => [5]}).turn == "c"

      opener_out =
        %{"a" => 5, "b" => 1, "c" => 1}
        |> holding(%{"a" => [1, 1, 1, 1, 1], "b" => [2], "c" => [3]})
        |> lose!("a", "b")
        |> Game.without_round()

      assert %{opener: "b", out: ["a"]} = opener_out
    end

    test "two Penalty dice on three sixes stay, and a Player they Knocked out stays out" do
      between =
        %{"a" => 1, "b" => 5, "c" => 1}
        |> holding(%{"a" => [2], "b" => [1, 1, 1, 1, 1], "c" => [3]})
        |> raise!("a", 1, 2)
        |> raise!("b", 3, 6)
        |> check!("c")
        |> Game.advance_reveal(3)
        |> Game.without_round()

      assert_no_round(between)
      assert between.counts == %{"a" => 1, "b" => 7, "c" => 1}
      assert %{opener: "c", out: ["b"]} = between
      assert Game.to_roll(between) == [{"a", 1}, {"c", 1}]

      between =
        round_one()
        |> raise!("a", 3, 6)
        |> check!("b")
        |> Game.advance_reveal(3)
        |> Game.without_round()

      assert between.counts == %{"a" => 3, "b" => 1, "c" => 1}
      assert %{opener: "a", out: []} = between
    end

    test "a re-roll voided by a leave keeps its opener, and the save no longer names the leaver" do
      {:void, game} = round_one() |> raise!("a", 1, 5) |> Game.leave("b")
      rerolled = Game.start_round(game, %{"a" => [3], "c" => [4]})

      between = Game.without_round(rerolled)

      assert %{opener: "c", voided_by: nil} = between

      assert %{turn: "c", opener: "c", voided_by: nil} =
               Game.start_round(between, %{"a" => [1], "c" => [2]})
    end
  end

  test "the dice to roll are each seat's count, in seat order" do
    assert ["c", "a", "b"] |> Game.new() |> Game.to_roll() == [{"c", 1}, {"a", 1}, {"b", 1}]

    game = round_one() |> raise!("a", 3, 5) |> check!("b") |> Game.advance_reveal(3)

    assert Game.to_roll(game) == [{"a", 2}, {"b", 1}, {"c", 1}]
  end

  describe "playing blind" do
    test "a Round is dealt blind to the seats asked for that are in play, a Knocked-out one not" do
      game =
        ["a", "b", "c"]
        |> Game.new()
        |> Game.start_round(%{"a" => [2], "b" => [5], "c" => [5]}, ["c", "a", "z"])

      assert %{blind: ["a", "c"], peeked: [], bid_blind?: false} = game
      assert round_one().blind == []

      game =
        %{"a" => 5, "b" => 1, "c" => 1}
        |> holding(%{"a" => [1, 1, 1, 1, 1], "b" => [2], "c" => [3]})
        |> lose!("a", "b")
        |> Game.start_round(%{"b" => [2], "c" => [3]}, ["a", "b"])

      assert game.blind == ["b"]
    end

    defp blind_round do
      ["a", "b", "c"]
      |> Game.new()
      |> Game.start_round(%{"a" => [2], "b" => [5], "c" => [5]}, ["a", "b"])
    end

    test "a peek moves the seat from blind to peeked, and only a blind seat can peek" do
      assert {:ok, game} = Game.peek(blind_round(), "b")
      assert %{blind: ["a"], peeked: ["b"]} = game

      assert Game.peek(game, "b") == {:error, :not_blind}
      assert Game.peek(game, "c") == {:error, :not_blind}
      assert Game.peek(game, "z") == {:error, :not_blind}
    end

    test "a peek is refused once a Check is made, and with no Round dealt" do
      checked = blind_round() |> raise!("a", 1, 5) |> check!("b")

      assert Game.peek(checked, "a") == {:error, :not_bidding}
      assert Game.peek(Game.advance_reveal(checked, 3), "a") == {:error, :not_bidding}
      assert Game.peek(Game.without_round(blind_round()), "a") == {:error, :not_bidding}
      assert Game.peek(Game.new(["a", "b"]), "a") == {:error, :not_bidding}
    end

    test "a Bid is blind when its bidder is blind as they Raise, not once they peeked or when sighted" do
      game = raise!(blind_round(), "a", 1, 5)
      assert game.bid_blind?

      {:ok, game} = Game.peek(game, "b")
      game = raise!(game, "b", 1, 6)
      refute game.bid_blind?

      game = raise!(game, "c", 2, 1)
      refute game.bid_blind?

      assert raise!(game, "a", 2, 2).bid_blind?
    end

    test "changes no rule: blind seats Raise, Check and take the Penalty die as anyone does" do
      game = blind_round() |> raise!("a", 2, 5) |> raise!("b", 3, 5) |> check!("c")

      assert %{count: 2, stood?: false, loser: "b", checker: "c"} = game.reveal

      game = Game.advance_reveal(game, 3)

      assert game.counts == %{"a" => 1, "b" => 2, "c" => 1}
      assert Game.start_round(game, %{"a" => [1], "b" => [1, 1], "c" => [1]}).turn == "b"
    end

    test "a save and a void clear the blind, the peeked and the blind Bid" do
      {:ok, game} = blind_round() |> raise!("a", 1, 5) |> Game.peek("b")

      assert %{blind: [], peeked: [], bid_blind?: false} = Game.without_round(game)

      assert {:void, voided} = Game.leave(game, "c")
      assert %{blind: [], peeked: [], bid_blind?: false} = voided

      assert %{blind: ["a"], peeked: []} =
               Game.start_round(voided, %{"a" => [3], "b" => [4]}, ["a", "c"])
    end

    test "a seat moved to another person stays blind, or peeked, as that person" do
      {:ok, game} = Game.peek(blind_round(), "b")

      assert %{blind: ["z"], peeked: ["b"]} = Game.move_seat(game, "a", "z")
      assert %{blind: ["a"], peeked: ["y"]} = Game.move_seat(game, "b", "y")
    end
  end

  describe "moving a seat to another person" do
    test "mid-bidding, the seat, its dice, what it said, the Bid and the opening follow the person" do
      game = round_one() |> raise!("a", 1, 5) |> Game.move_seat("a", "z")

      assert game.seats == ["z", "b", "c"]
      assert game.counts == %{"z" => 1, "b" => 1, "c" => 1}
      assert game.dice == %{"z" => [2], "b" => [5], "c" => [5]}
      assert game.said == %{"z" => %{count: 1, face: 5}}
      assert game.bid == %{count: 1, face: 5, by: "z"}
      assert %{turn: "b", opener: "z", round: 1} = game

      game = game |> raise!("b", 1, 6) |> raise!("c", 2, 2)

      assert game.turn == "z"
    end

    test "the Player on turn keeps the turn as the new person" do
      game = round_one() |> raise!("a", 1, 5) |> Game.move_seat("b", "z")

      assert game.turn == "z"
      assert {:ok, %{bid: %{by: "z"}, turn: "c"}} = Game.raise(game, "z", 2, 5)
      assert Game.raise(game, "b", 2, 5) == {:error, :not_your_turn}
    end

    test "mid-reveal, the Check, its loser, its Bid and the kept Check follow the person" do
      checked = round_one() |> raise!("a", 3, 5) |> check!("b")
      game = Game.move_seat(checked, "a", "z")

      assert %{checker: "b", loser: "z", bid: %{by: "z"}, step: 0} = game.reveal

      game = Game.advance_reveal(game, 3)

      assert game.counts == %{"z" => 2, "b" => 1, "c" => 1}
      assert game.checks == [%{round: 1, checker: "b", bidder: "z", stood?: false}]
      assert Game.start_round(game, %{"z" => [1, 1], "b" => [1], "c" => [1]}).turn == "z"

      settled = checked |> Game.advance_reveal(3) |> Game.move_seat("b", "y")

      assert %{checker: "y", loser: "a"} = settled.reveal
      assert settled.checks == [%{round: 1, checker: "y", bidder: "a", stood?: false}]
    end

    test "a Knocked-out seat and a voided Round name the new person" do
      {:void, game} = round_one() |> raise!("a", 1, 5) |> Game.leave("b")
      game = Game.move_seat(game, "b", "z")

      assert %{out: ["z"], voided_by: "z", seats: ["a", "z", "c"]} = game
      assert Game.start_round(game, %{"a" => [3], "c" => [4]}).turn == "c"
    end

    test "onto a person whose seat is Knocked out swaps the two seats, nobody's place moving" do
      game = Game.move_seat(a_knocked_out(), "c", "a")

      assert game.seats == ["c", "b", "a", "d"]
      assert game.out == ["c"]
      assert game.counts == %{"a" => 1, "b" => 1, "c" => 6, "d" => 5}
      assert game.dice == %{"a" => [3], "b" => [2], "d" => [4, 4, 4, 4, 4]}
      assert game.checks == [%{round: 1, checker: "b", bidder: "c", stood?: false}]

      game = game |> raise!("b", 1, 2)

      assert game.turn == "a"
      assert Game.to_roll(game) == [{"b", 1}, {"a", 1}, {"d", 5}]
    end

    test "of someone not in the Game changes nothing" do
      game = raise!(round_one(), "a", 1, 5)

      assert Game.move_seat(game, "x", "z") == game
    end
  end
end
