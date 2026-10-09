defmodule ThreeSixes.Dice do
  @callback roll(count :: pos_integer()) :: [1..6]
  @callback shuffle(list()) :: list()

  def roll(count), do: roller().roll(count)

  def shuffle(list), do: roller().shuffle(list)

  defp roller, do: Application.fetch_env!(:three_sixes, :dice)
end
