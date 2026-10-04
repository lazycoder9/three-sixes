defmodule ThreeSixes.Rooms do
  alias ThreeSixes.Room
  alias ThreeSixes.RoomCode
  alias ThreeSixes.Rooms.Server

  @code_attempts 10

  @spec create(Room.person_id()) :: {:ok, String.t()} | {:error, :busy}
  def create(host_id), do: create(host_id, @code_attempts)

  defp create(_host_id, 0), do: {:error, :busy}

  defp create(host_id, attempts) do
    code = RoomCode.random()

    case DynamicSupervisor.start_child(ThreeSixes.Rooms.Supervisor, {Server, {code, host_id}}) do
      {:ok, _pid} -> {:ok, code}
      {:error, {:already_started, _pid}} -> create(host_id, attempts - 1)
      {:error, :max_children} -> {:error, :busy}
    end
  end

  @spec join(String.t(), Room.person_id()) :: {:ok, Room.view()} | {:error, :closed}
  def join(code, person_id), do: call(code, {:join, self(), person_id})

  @spec enter(String.t(), Room.person_id(), String.t()) ::
          {:ok, Room.view()}
          | {:taken, held :: String.t(), suggestion :: String.t()}
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
    :exit, {reason, _} when reason in [:noproc, :normal] -> {:error, :closed}
  end
end
