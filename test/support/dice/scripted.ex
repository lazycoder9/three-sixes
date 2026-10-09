defmodule ThreeSixes.Dice.Scripted do
  @behaviour ThreeSixes.Dice

  use Agent

  def start_link(_opts \\ []), do: Agent.start_link(fn -> %{} end, name: __MODULE__)

  def script(rolls) when is_list(rolls), do: queue(:roll, rolls)

  def script_seats(order) when is_list(order), do: queue(:seats, [order])

  defp queue(kind, items) do
    key = {kind, self()}
    Agent.update(__MODULE__, &Map.update(&1, key, items, fn queued -> queued ++ items end))
  end

  @impl true
  def roll(count) do
    case next(:roll) do
      faces when length(faces) == count -> faces
      nil -> raise "no roll scripted for #{inspect(owners())}"
      faces -> raise "scripted roll #{inspect(faces)} does not have #{count} dice"
    end
  end

  @impl true
  def shuffle(list) do
    case next(:seats) do
      nil ->
        list

      order ->
        if Enum.sort(order) != Enum.sort(list),
          do: raise("scripted seats #{inspect(order)} are not #{inspect(list)}")

        order
    end
  end

  defp next(kind) do
    owners = owners()
    Agent.get_and_update(__MODULE__, &take(&1, kind, owners))
  end

  defp owners, do: [self() | Process.get(:"$callers", [])]

  defp take(scripts, kind, owners) do
    case Enum.find(owners, &match?([_ | _], scripts[{kind, &1}])) do
      nil -> {nil, scripts}
      owner -> Map.get_and_update!(scripts, {kind, owner}, fn [item | rest] -> {item, rest} end)
    end
  end
end
