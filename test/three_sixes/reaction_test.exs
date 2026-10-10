defmodule ThreeSixes.ReactionTest do
  use ExUnit.Case, async: true

  alias ThreeSixes.Reaction

  test "the set is the five faces, then GG, No way and Check it!, in the note's order" do
    assert Reaction.all() == ~w(lol gasp hmm clap fire gg noway checkit)

    assert Enum.map(Reaction.all(), &Reaction.text/1) ==
             ["😂", "😱", "🤨", "👏", "🔥", "GG", "No way", "Check it!"]
  end

  test "a key outside the set has no text" do
    assert Reaction.text("wave") == nil
    assert Reaction.text("") == nil
    assert Reaction.text(nil) == nil
    assert Reaction.text(:lol) == nil
  end
end
