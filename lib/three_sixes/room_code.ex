defmodule ThreeSixes.RoomCode do
  @alphabet "BCDFHJKLMNPQRSTVWXZ"
  @letters String.graphemes(@alphabet)
  @length 4

  @spec alphabet() :: String.t()
  def alphabet, do: @alphabet

  @spec normalize(String.t()) :: String.t()
  def normalize(input), do: input |> String.upcase() |> String.replace(~r/[^A-Z]/, "")

  @spec valid?(String.t()) :: boolean()
  def valid?(code) do
    letters = String.graphemes(code)
    length(letters) == @length and Enum.all?(letters, &(&1 in @letters))
  end

  @spec random() :: String.t()
  def random, do: Enum.map_join(1..@length, fn _ -> Enum.random(@letters) end)
end
