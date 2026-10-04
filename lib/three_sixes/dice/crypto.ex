defmodule ThreeSixes.Dice.Crypto do
  @behaviour ThreeSixes.Dice

  @impl true
  def roll(count), do: Enum.map(1..count//1, fn _ -> face() end)

  # Bytes from 252 up are drawn again, because keeping them would favour faces 1 to 4.
  defp face do
    <<byte>> = :crypto.strong_rand_bytes(1)
    if byte < 252, do: rem(byte, 6) + 1, else: face()
  end
end
