defmodule ThreeSixes.RoomCodeTest do
  use ExUnit.Case, async: true

  alias ThreeSixes.RoomCode

  test "the alphabet is consonants that cannot be read as another letter or a digit" do
    assert RoomCode.alphabet() == "BCDFHJKLMNPQRSTVWXZ"
  end

  test "normalize upcases and drops everything that is not a letter" do
    assert RoomCode.normalize("kqxt") == "KQXT"
    assert RoomCode.normalize(" k-q x.t ") == "KQXT"
    assert RoomCode.normalize("kq1xt!") == "KQXT"
    assert RoomCode.normalize("") == ""
  end

  test "a valid code is four letters from the alphabet" do
    assert RoomCode.valid?("KQXT")
    refute RoomCode.valid?("KQX")
    refute RoomCode.valid?("KQXTB")
    refute RoomCode.valid?("KQXA")
    refute RoomCode.valid?("kqxt")
    refute RoomCode.valid?("")
  end

  test "a random code is always valid" do
    for _ <- 1..500, do: assert(RoomCode.valid?(RoomCode.random()))
  end
end
