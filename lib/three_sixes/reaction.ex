defmodule ThreeSixes.Reaction do
  @set [
    {"lol", "😂"},
    {"gasp", "😱"},
    {"hmm", "🤨"},
    {"clap", "👏"},
    {"fire", "🔥"},
    {"gg", "GG"},
    {"noway", "No way"},
    {"checkit", "Check it!"}
  ]

  @type key :: String.t()

  @spec all() :: [key()]
  def all, do: Enum.map(@set, &elem(&1, 0))

  @spec text(term()) :: String.t() | nil
  for {key, text} <- @set do
    def text(unquote(key)), do: unquote(text)
  end

  def text(_key), do: nil
end
