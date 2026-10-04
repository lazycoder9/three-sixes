defmodule ThreeSixes.Room do
  @enforce_keys [:code, :host_id]
  @max_nickname_length 16
  @capacity 30

  defstruct [:code, :host_id, members: []]

  @type person_id :: String.t()
  @type member :: %{id: person_id(), nickname: String.t()}
  @type view :: %{
          code: String.t(),
          people: [%{nickname: String.t(), host?: boolean(), me?: boolean(), n: pos_integer()}],
          me: String.t() | nil,
          host?: boolean()
        }
  @type t :: %__MODULE__{code: String.t(), host_id: person_id(), members: [member()]}

  @spec new(String.t(), person_id()) :: t()
  def new(code, host_id), do: %__MODULE__{code: code, host_id: host_id}

  @spec enter(t(), person_id(), String.t()) ::
          {:ok, t()}
          | {:taken, held :: String.t(), suggestion :: String.t()}
          | {:error, :blank | :too_long | :full}
  def enter(room, person_id, nickname) do
    cond do
      member?(room, person_id) -> {:ok, room}
      length(room.members) >= @capacity -> {:error, :full}
      true -> add(room, person_id, nickname)
    end
  end

  defp add(room, person_id, nickname) do
    with {:ok, nickname} <- clean(nickname) do
      case holder(room, nickname) do
        nil -> {:ok, %{room | members: room.members ++ [%{id: person_id, nickname: nickname}]}}
        holder -> {:taken, holder.nickname, suggestion(room, holder.nickname)}
      end
    end
  end

  defp clean(nickname) when not is_binary(nickname), do: {:error, :blank}

  defp clean(nickname) do
    nickname = String.trim(nickname)

    cond do
      nickname == "" -> {:error, :blank}
      String.length(nickname) > @max_nickname_length -> {:error, :too_long}
      true -> {:ok, nickname}
    end
  end

  defp holder(room, nickname) do
    wanted = String.downcase(nickname)
    Enum.find(room.members, &(String.downcase(&1.nickname) == wanted))
  end

  defp suggestion(room, held) do
    base = String.replace(held, ~r/ \d+$/u, "")

    2
    |> Stream.iterate(&(&1 + 1))
    |> Stream.map(&numbered(base, &1))
    |> Enum.find(&(holder(room, &1) == nil))
  end

  defp numbered(base, number) do
    suffix = " #{number}"

    base =
      base
      |> String.slice(0, @max_nickname_length - String.length(suffix))
      |> String.trim_trailing()

    base <> suffix
  end

  @spec member?(t(), person_id()) :: boolean()
  def member?(room, person_id), do: Enum.any?(room.members, &(&1.id == person_id))

  @spec view_for(t(), person_id()) :: view()
  def view_for(room, person_id) do
    me = Enum.find(room.members, &(&1.id == person_id))

    %{
      code: room.code,
      people:
        room.members
        |> Enum.with_index(1)
        |> Enum.map(fn {member, n} ->
          %{
            nickname: member.nickname,
            host?: member.id == room.host_id,
            me?: member.id == person_id,
            n: n
          }
        end),
      me: me && me.nickname,
      host?: person_id == room.host_id
    }
  end
end
