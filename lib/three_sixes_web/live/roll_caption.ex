defmodule ThreeSixesWeb.RollCaption do
  @counts ~w(one two three)
  @faces ~w(one two three four five six)

  @doc """
  Reads a roll of three dice back as the best Bid it truthfully supports.
  """
  def for_faces(faces) do
    case best_bid(faces) do
      {3, 6} -> "Three sixes. For real this time!"
      {3, face} -> "#{bid_words(3, face)}. Honest, for once."
      {2, face} -> "#{bid_words(2, face)}. You could say three."
      {1, _face} -> "No pair. Bluff anyway."
    end
  end

  defp best_bid(faces) do
    faces
    |> Enum.frequencies()
    |> Enum.max_by(fn {face, count} -> {count, face} end)
    |> then(fn {face, count} -> {count, face} end)
  end

  defp bid_words(count, face) do
    String.capitalize("#{Enum.at(@counts, count - 1)} #{plural(Enum.at(@faces, face - 1))}")
  end

  defp plural("six"), do: "sixes"
  defp plural(face), do: face <> "s"
end
