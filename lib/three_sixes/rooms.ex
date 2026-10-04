defmodule ThreeSixes.Rooms do
  alias ThreeSixes.Room
  alias ThreeSixes.RoomCode
  alias ThreeSixes.Rooms.Server

  @spec create(Room.person_id()) :: {:ok, String.t()}
  def create(host_id) do
    code = RoomCode.random()

    case DynamicSupervisor.start_child(ThreeSixes.Rooms.Supervisor, {Server, {code, host_id}}) do
      {:ok, _pid} -> {:ok, code}
      {:error, {:already_started, _pid}} -> create(host_id)
    end
  end

  @spec join(String.t(), Room.person_id()) :: {:ok, Room.view()} | {:error, :closed}
  def join(code, person_id), do: call(code, {:join, self(), person_id})

  @spec enter(String.t(), Room.person_id(), String.t()) ::
          {:ok, Room.view()}
          | {:taken, String.t()}
          | {:error, :blank | :too_long | :full | :closed}
  def enter(code, person_id, nickname), do: call(code, {:enter, person_id, nickname})

  @spec whereis(String.t()) :: pid() | nil
  def whereis(code) do
    case Registry.lookup(ThreeSixes.Rooms.Registry, code) do
      [{pid, _value}] -> pid
      [] -> nil
    end
  end

  defp call(code, request) do
    GenServer.call(Server.via(code), request)
  catch
    :exit, {:noproc, _} -> {:error, :closed}
  end
end
