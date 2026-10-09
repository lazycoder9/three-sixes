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
           {Server, {code, host_id, address, [self() | Process.get(:"$callers", [])]}}
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

  @spec sit_out(String.t(), Room.person_id(), boolean()) ::
          :ok | {:error, :not_member | :closed}
  def sit_out(code, person_id, sitting_out?), do: call(code, {:sit_out, person_id, sitting_out?})

  @spec start_game(String.t(), Room.person_id()) ::
          :ok | {:error, :not_host | :playing | :too_few | :closed}
  def start_game(code, person_id), do: call(code, {:start_game, person_id})

  @spec raise(String.t(), Room.person_id(), term(), term()) ::
          :ok | {:error, :not_bidding | :not_your_turn | :illegal | :closed}
  def raise(code, person_id, count, face), do: call(code, {:raise, person_id, count, face})

  @spec check(String.t(), Room.person_id()) ::
          :ok | {:error, :not_bidding | :not_your_turn | :no_bid | :closed}
  def check(code, person_id), do: call(code, {:check, person_id})

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
