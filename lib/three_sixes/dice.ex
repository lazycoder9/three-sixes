defmodule ThreeSixes.Dice do
  @callback roll(count :: pos_integer()) :: [1..6]

  def roll(count), do: roller().roll(count)

  defp roller, do: Application.fetch_env!(:three_sixes, :dice)
end
