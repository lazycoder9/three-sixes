defmodule ThreeSixesWeb.RollCaptionTest do
  use ExUnit.Case, async: true

  alias ThreeSixesWeb.RollCaption

  test "three sixes" do
    assert RollCaption.for_faces([6, 6, 6]) == "Three sixes. For real this time!"
  end

  test "three of any other face" do
    assert RollCaption.for_faces([4, 4, 4]) == "Three fours. Honest, for once."
    assert RollCaption.for_faces([1, 1, 1]) == "Three ones. Honest, for once."
  end

  test "a pair is read back as the Bid it supports, whatever the order" do
    assert RollCaption.for_faces([5, 2, 5]) == "Two fives. You could say three."
    assert RollCaption.for_faces([1, 3, 3]) == "Two threes. You could say three."
  end

  test "a pair of sixes takes the plural sixes" do
    assert RollCaption.for_faces([6, 1, 6]) == "Two sixes. You could say three."
  end

  test "no pair" do
    assert RollCaption.for_faces([1, 4, 6]) == "No pair. Bluff anyway."
  end
end
