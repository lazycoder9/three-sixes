defmodule ThreeSixes.Rooms do
  import Ecto.Query

  require Logger

  alias ThreeSixes.Repo
  alias ThreeSixes.Room
  alias ThreeSixes.RoomCode
  alias ThreeSixes.Rooms.Save
  alias ThreeSixes.Rooms.Server

  @code_attempts 10

  @spec create(Room.person_id(), String.t()) :: {:ok, String.t()} | {:error, :busy | :too_many}
  def create(host_id, address), do: create(host_id, address, @code_attempts)

  defp create(_host_id, _address, 0), do: {:error, :busy}

  defp create(host_id, address, attempts) do
    code = RoomCode.random()

    if open?(code) do
      create(host_id, address, attempts - 1)
    else
      delete_save(code)

      case start(code, {host_id, address}) do
        {:ok, _pid} -> {:ok, code}
        {:error, {:already_started, _pid}} -> create(host_id, address, attempts - 1)
        {:error, :max_children} -> {:error, :busy}
        {:error, :too_many} -> {:error, :too_many}
      end
    end
  end

  defp start(code, creator) do
    DynamicSupervisor.start_child(
      ThreeSixes.Rooms.Supervisor,
      {Server, {code, creator, [self() | Process.get(:"$callers", [])]}}
    )
  end

  @spec join(String.t(), Room.person_id(), was :: Room.person_id() | nil) ::
          {:ok | :moved, Room.view()} | {:error, :closed}
  def join(code, person_id, was \\ nil), do: call(code, {:join, self(), person_id, was})

  @spec enter(String.t(), Room.person_id(), String.t()) ::
          {:ok, Room.view()}
          | {:taken, held :: String.t(), suggestion :: String.t()}
          | {:error, :blank | :too_long | :full | :closed}
  def enter(code, person_id, nickname), do: call(code, {:enter, person_id, nickname})

  @spec sit_out(String.t(), Room.person_id(), boolean()) ::
          :ok | {:error, :not_member | :closed}
  def sit_out(code, person_id, sitting_out?), do: call(code, {:sit_out, person_id, sitting_out?})

  @spec blind(String.t(), Room.person_id(), boolean()) :: :ok | {:error, :not_member | :closed}
  def blind(code, person_id, on?), do: call(code, {:blind, person_id, on?})

  @spec peek(String.t(), Room.person_id()) ::
          :ok | {:error, :not_bidding | :not_blind | :closed}
  def peek(code, person_id), do: call(code, {:peek, person_id})

  @spec start_game(String.t(), Room.person_id()) ::
          :ok | {:error, :not_host | :playing | :too_few | :closed}
  def start_game(code, person_id), do: call(code, {:start_game, person_id})

  @spec raise(String.t(), Room.person_id(), term(), term()) ::
          :ok | {:error, :not_bidding | :not_your_turn | :illegal | :closed}
  def raise(code, person_id, count, face), do: call(code, {:raise, person_id, count, face})

  @spec check(String.t(), Room.person_id()) ::
          :ok | {:error, :not_bidding | :not_your_turn | :no_bid | :closed}
  def check(code, person_id), do: call(code, {:check, person_id})

  @spec leave(String.t(), Room.person_id()) :: :ok | {:error, :not_member | :closed}
  def leave(code, person_id), do: call(code, {:leave, person_id})

  @spec remove(String.t(), Room.person_id(), pos_integer()) ::
          :ok | {:error, :not_host | :not_member | :self | :closed}
  def remove(code, by, n), do: call(code, {:remove, by, n})

  @spec make_host(String.t(), Room.person_id(), pos_integer()) ::
          :ok | {:error, :not_host | :not_member | :self | :closed}
  def make_host(code, by, n), do: call(code, {:make_host, by, n})

  @spec start_vote(String.t(), Room.person_id()) ::
          :ok | {:error, :no_handover | :not_member | :voting | :too_soon | :closed}
  def start_vote(code, person_id), do: call(code, {:start_vote, person_id})

  @spec vote(String.t(), Room.person_id(), boolean()) ::
          :ok | {:error, :no_vote | :not_member | :closed}
  def vote(code, person_id, yes?), do: call(code, {:vote, person_id, yes?})

  @spec react(String.t(), Room.person_id(), term()) ::
          :ok | {:error, :not_member | :unknown | :too_soon | :closed}
  def react(code, person_id, key), do: call(code, {:react, person_id, key})

  @spec whereis(String.t()) :: pid() | nil
  def whereis(code) do
    case Registry.lookup(ThreeSixes.Rooms.Registry, code) do
      [{pid, _value}] -> pid
      [] -> nil
    end
  end

  @spec open?(String.t()) :: boolean()
  def open?(code), do: whereis(code) != nil or live_save(code, DateTime.utc_now()) != nil

  @spec save(String.t(), Room.t(), DateTime.t() | nil) :: :ok
  def save(code, room, closes_at) do
    Repo.insert!(
      %Save{code: code, room: :erlang.term_to_binary(Room.to_save(room)), closes_at: closes_at},
      on_conflict: {:replace_all_except, [:code, :inserted_at]},
      conflict_target: :code
    )

    :ok
  end

  @spec saved(String.t()) :: {:ok, Room.t(), DateTime.t() | nil} | :none
  def saved(code), do: Save |> Repo.get(code) |> decoded()

  @spec delete_save(String.t()) :: :ok
  def delete_save(code) do
    Repo.delete_all(from save in Save, where: save.code == ^code)
    :ok
  end

  defp live_save(code, now) do
    case Repo.get(Save, code) do
      %Save{} = save -> if live?(save, now) and decoded(save) != :none, do: save
      nil -> nil
    end
  end

  defp live?(%{closes_at: nil, updated_at: updated_at}, now),
    do: DateTime.diff(now, updated_at, :millisecond) < Server.close_after()

  defp live?(%{closes_at: closes_at}, now), do: DateTime.after?(closes_at, now)

  defp decoded(nil), do: :none

  defp decoded(save) do
    {:ok, Plug.Crypto.non_executable_binary_to_term(save.room), save.closes_at}
  rescue
    ArgumentError ->
      Logger.warning("Room #{save.code} has a save that cannot be read")
      :none
  end

  defp call(code, request, restore? \\ true) do
    GenServer.call(Server.via(code), request)
  catch
    :exit, {:noproc, _} when restore? ->
      if restored?(code), do: call(code, request, false), else: {:error, :closed}

    :exit, {reason, _} when reason in [:noproc, :normal] ->
      {:error, :closed}
  end

  defp restored?(code) do
    live_save(code, DateTime.utc_now()) != nil and
      case start(code, nil) do
        {:ok, _pid} -> true
        {:error, {:already_started, _pid}} -> true
        _closed_or_busy -> false
      end
  end
end
