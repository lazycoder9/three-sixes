defmodule ThreeSixes.Dice.Scripted do
  @behaviour ThreeSixes.Dice

  use Agent

  def start_link(_opts \\ []), do: Agent.start_link(fn -> %{} end, name: __MODULE__)

  def script(rolls) when is_list(rolls) do
    owner = self()
    Agent.update(__MODULE__, &Map.update(&1, owner, rolls, fn queued -> queued ++ rolls end))
  end

  @impl true
  def roll(count) do
    owners = [self() | Process.get(:"$callers", [])]

    case Agent.get_and_update(__MODULE__, &next_roll(&1, owners)) do
      faces when length(faces) == count -> faces
      nil -> raise "no roll scripted for #{inspect(owners)}"
      faces -> raise "scripted roll #{inspect(faces)} does not have #{count} dice"
    end
  end

  defp next_roll(scripts, owners) do
    case Enum.find(owners, &match?([_ | _], scripts[&1])) do
      nil -> {nil, scripts}
      owner -> Map.get_and_update!(scripts, owner, fn [faces | rest] -> {faces, rest} end)
    end
  end
end
