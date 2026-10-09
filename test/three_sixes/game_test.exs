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
    test "with no Bid, one row of every face, from one die" do
      assert Game.offers(nil, 4, 0) == [
               %{count: 1, faces: [1, 2, 3, 4, 5, 6], step?: true, at_max?: false}
             ]
    end

    test "a Bid offers its count with the higher faces, then one more of every face" do
      assert Game.offers(@bid, 7, 0) == [
               %{count: 3, faces: [5, 6]},
               %{count: 4, faces: [1, 2, 3, 4, 5, 6], step?: true, at_max?: false}
             ]
    end

    test "a Bid on sixes has no first row" do
      assert Game.offers(%{count: 2, face: 6}, 5, 0) == [
               %{count: 3, faces: [1, 2, 3, 4, 5, 6], step?: true, at_max?: false}
             ]
    end

    test "the second row is absent when one more would not fit on the table" do
      assert Game.offers(%{count: 4, face: 2}, 4, 0) == [%{count: 4, faces: [3, 4, 5, 6]}]
      assert Game.offers(%{count: 4, face: 6}, 4, 0) == []
    end

    test "the second row at the dice on the table cannot step" do
      assert Game.offers(%{count: 3, face: 2}, 4, 0) == [
               %{count: 3, faces: [3, 4, 5, 6]},
               %{count: 4, faces: [1, 2, 3, 4, 5, 6], step?: false, at_max?: true}
             ]
    end

    test "the step raises the second row, clamped between none and the dice on the table" do
      assert [_, %{count: 6, at_max?: false}] = Game.offers(@bid, 7, 2)
      assert [_, %{count: 7, at_max?: true}] = Game.offers(@bid, 7, 3)
      assert [_, %{count: 7, at_max?: true}] = Game.offers(@bid, 7, 99)
      assert [_, %{count: 4, at_max?: false}] = Game.offers(@bid, 7, -5)
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
        |> raise!("a", 3, 6)
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

  test "the dice to roll are each seat's count, in seat order" do
    assert ["c", "a", "b"] |> Game.new() |> Game.to_roll() == [{"c", 1}, {"a", 1}, {"b", 1}]

    game = round_one() |> raise!("a", 3, 5) |> check!("b") |> Game.advance_reveal(3)

    assert Game.to_roll(game) == [{"a", 2}, {"b", 1}, {"c", 1}]
  end
end
