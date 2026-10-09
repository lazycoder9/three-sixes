defmodule ThreeSixes.Dice.CryptoTest do
  use ExUnit.Case, async: true

  alias ThreeSixes.Dice.Crypto

  test "a shuffle returns the same people, each once" do
    people = Enum.map(1..30, &"guest:#{&1}")

    shuffled = Crypto.shuffle(people)

    assert length(shuffled) == 30
    assert Enum.sort(shuffled) == Enum.sort(people)
    assert Crypto.shuffle([]) == []
  end
end
