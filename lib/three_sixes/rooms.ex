defmodule ThreeSixes.Rooms do
  alias ThreeSixes.Room
  alias ThreeSixes.RoomCode
  alias ThreeSixes.Rooms.Server

  @code_attempts 10

  @spec create(Room.person_id(), String.t()) :: {:ok, String.t()} | {:error, :busy | :too_many}
  def create(host_id, address), do: create(host_id, address, @code_attempts)

  defp create(_host_id, _address, 0), do: {:error, :busy}

  defp create(host_id, address, attempts) do
    code = RoomCode.random()

    case DynamicSupervisor.start_child(
           ThreeSixes.Rooms.Supervisor,
           {Server, {code, host_id, address}}
         ) do
      {:ok, _pid} -> {:ok, code}
      {:error, {:already_started, _pid}} -> create(host_id, address, attempts - 1)
      {:error, :max_children} -> {:error, :busy}
      {:error, :too_many} -> {:error, :too_many}
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
