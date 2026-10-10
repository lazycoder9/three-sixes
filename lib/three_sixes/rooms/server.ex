defmodule ThreeSixes.Rooms.Server do
  use GenServer, restart: :transient

  require Logger

  alias ThreeSixes.Dice
  alias ThreeSixes.Game
  alias ThreeSixes.Reaction
  alias ThreeSixes.Records
  alias ThreeSixes.Room
  alias ThreeSixes.Rooms

  @close_after :timer.minutes(15)
  @reaction_wait 2000
  @save_after :timer.seconds(5)
  @refresh_after :timer.minutes(5)
  @open_per_guest 5
  @open_per_address 20

  @type creator :: {Room.person_id(), address :: String.t()} | nil

  @spec start_link({String.t(), creator(), [pid()]}) :: GenServer.on_start()
  def start_link({code, creator, callers}) do
    GenServer.start_link(__MODULE__, {code, creator, callers},
      name: {:via, Registry, {ThreeSixes.Rooms.Registry, code, creator || :restored}}
    )
  end

  @spec via(String.t()) :: GenServer.name()
  def via(code), do: {:via, Registry, {ThreeSixes.Rooms.Registry, code}}

  @spec close_after() :: pos_integer()
  def close_after, do: @close_after

  @impl true
  def init({code, creator, callers}) do
    Process.put(:"$callers", callers)
    Process.flag(:trap_exit, true)

    case Rooms.saved(code) do
      {:ok, saved, closes_at} -> {:ok, restored(saved, closes_at)}
      :none when creator == nil -> :ignore
      :none -> new(code, creator)
    end
  rescue
    error ->
      Logger.error("Room #{code} could not be restored: #{Exception.message(error)}")
      :ignore
  end

  defp restored(saved, closes_at) do
    case Room.restore(saved) do
      {:roll, room} ->
        room |> roll() |> state(closes_at) |> all_away() |> unsaved()

      {:ok, room} ->
        room
        |> state(closes_at)
        |> all_away()
        |> finished_on_restore(Room.finished(saved, room))
    end
  end

  defp all_away(%{room: room} = state) do
    at = state.now.()
    changed_if_new(state, Enum.reduce(room.members, room, &Room.away(&2, &1.id, at)))
  end

  defp finished_on_restore(state, nil), do: state

  defp finished_on_restore(state, game) do
    record(game)
    unsaved(state)
  end

  defp new(code, {host_id, address}) do
    if open({host_id, :_}) > @open_per_guest or open({:_, address}) > @open_per_address do
      {:stop, :too_many}
    else
      {:ok, state(Room.new(code, host_id), nil)}
    end
  end

  defp state(room, closes_at) do
    schedule_close(%{
      room: room,
      joined: %{},
      close_timer: nil,
      reveal_timers: [],
      waiting: MapSet.new(),
      now: fn -> System.system_time(:millisecond) end,
      closes_at: closes_at,
      changed?: false,
      save_timer: nil,
      refresh_timer: nil
    })
  end

  @impl true
  def handle_call({:join, pid, person_id, was}, _from, state) do
    unless Map.has_key?(state.joined, pid), do: Process.monitor(pid)
    if state.close_timer, do: Process.cancel_timer(state.close_timer)
    {moved, room} = move_seat(state.room, was, person_id)
    state = state |> changed_if_new(Room.back(room, person_id)) |> stop_reveal()

    state =
      %{state | joined: Map.put(state.joined, pid, person_id), close_timer: nil}
      |> put_closes_at(nil)
      |> schedule_refresh()

    {:reply, {moved, Room.view_for(state.room, person_id)}, state}
  end

  def handle_call({:enter, person_id, nickname}, _from, state) do
    case Room.enter(state.room, person_id, nickname) do
      {:ok, room} when room == state.room ->
        {:reply, {:ok, Room.view_for(room, person_id)}, state}

      {:ok, room} ->
        {:reply, {:ok, Room.view_for(room, person_id)}, changed(state, room)}

      refused ->
        {:reply, refused, state}
    end
  end

  def handle_call({:sit_out, person_id, sitting_out?}, _from, state) do
    case Room.sit_out(state.room, person_id, sitting_out?) do
      {:ok, room} -> {:reply, :ok, changed(state, room)}
      refused -> {:reply, refused, state}
    end
  end

  def handle_call({:start_game, person_id}, _from, state) do
    seats = Dice.shuffle(Room.dealt_in(state.room))

    case Room.start_game(state.room, person_id, seats) do
      {:ok, room} -> {:reply, :ok, changed(state, roll(room))}
      refused -> {:reply, refused, state}
    end
  end

  def handle_call({:raise, person_id, count, face}, _from, state) do
    case Room.raise(state.room, person_id, count, face) do
      {:ok, room} -> {:reply, :ok, changed(state, room)}
      refused -> {:reply, refused, state}
    end
  end

  def handle_call({:check, person_id}, _from, state) do
    case Room.check(state.room, person_id) do
      {:ok, room} ->
        timers =
          for {delay, message} <- Room.reveal_schedule(room),
              do: Process.send_after(self(), message, delay)

        {:reply, :ok, changed(%{state | reveal_timers: timers}, room)}

      refused ->
        {:reply, refused, state}
    end
  end

  def handle_call({:leave, person_id}, _from, state) do
    case Room.leave(state.room, person_id, connected(state)) do
      {:roll, room} -> {:reply, :ok, changed(state, roll(room))}
      {:ok, room} -> {:reply, :ok, state |> changed(room) |> stop_reveal()}
      refused -> {:reply, refused, state}
    end
  end

  def handle_call({:remove, by, n}, _from, state) do
    case Room.remove(state.room, by, n, connected(state)) do
      {:roll, room} -> {:reply, :ok, state |> tell_removed(room) |> changed(roll(room))}
      {:ok, room} -> {:reply, :ok, state |> tell_removed(room) |> changed(room) |> stop_reveal()}
      refused -> {:reply, refused, state}
    end
  end

  def handle_call({:make_host, by, n}, _from, state) do
    case Room.make_host(state.room, by, n) do
      {:ok, room} -> {:reply, :ok, changed(state, room)}
      refused -> {:reply, refused, state}
    end
  end

  def handle_call({:react, person_id, key}, _from, state) do
    cond do
      not Room.member?(state.room, person_id) ->
        {:reply, {:error, :not_member}, state}

      Reaction.text(key) == nil ->
        {:reply, {:error, :unknown}, state}

      person_id in state.waiting ->
        {:reply, {:error, :too_soon}, state}

      true ->
        for {pid, viewer} <- state.joined do
          send(pid, {:reaction, %{by: Room.person_ref(state.room, person_id, viewer), key: key}})
        end

        Process.send_after(self(), {:reaction_ready, person_id}, @reaction_wait)
        {:reply, :ok, %{state | waiting: MapSet.put(state.waiting, person_id)}}
    end
  end

  @impl true
  def handle_info({:reveal, round, step}, state) do
    case Room.reveal(state.room, round, step) do
      {:ok, room} when room != state.room -> {:noreply, changed(state, room)}
      _stale_or_reached -> {:noreply, state}
    end
  end

  def handle_info({:next_round, round}, state) do
    case Room.next_round(state.room, round) do
      {:roll, room} -> {:noreply, changed(state, roll(room))}
      {:over, room} -> {:noreply, changed(state, room)}
      :stale -> {:noreply, state}
    end
  end

  def handle_info({:reaction_ready, person_id}, state),
    do: {:noreply, %{state | waiting: MapSet.delete(state.waiting, person_id)}}

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {person_id, joined} = Map.pop(state.joined, pid)
    state = %{state | joined: joined}

    state =
      if person_id in Map.values(joined),
        do: state,
        else: changed_if_new(state, Room.away(state.room, person_id, state.now.()))

    {:noreply, schedule_close(state)}
  end

  def handle_info({:timeout, timer, :close}, %{close_timer: timer} = state),
    do: {:stop, :normal, state}

  def handle_info({:timeout, _stale, :close}, state), do: {:noreply, state}

  def handle_info({:timeout, timer, :refresh}, %{refresh_timer: timer} = state),
    do: {:noreply, refresh(%{state | refresh_timer: nil})}

  def handle_info({:timeout, _stale, :refresh}, state), do: {:noreply, state}

  def handle_info(:save, state), do: {:noreply, save(%{state | save_timer: nil})}

  @impl true
  def terminate(:normal, state), do: quietly(state, fn -> Rooms.delete_save(state.room.code) end)
  def terminate(:shutdown, state), do: last_save(state)
  def terminate({:shutdown, _reason}, state), do: last_save(state)
  def terminate(_crash, _state), do: :ok

  defp last_save(state) do
    state
    |> put_closes_at(deadline(state, DateTime.utc_now()))
    |> save()
  end

  defp refresh(%{joined: joined} = state) when joined == %{}, do: state
  defp refresh(state), do: schedule_refresh(save(%{state | changed?: true}))

  defp schedule_refresh(%{refresh_timer: nil} = state),
    do: %{state | refresh_timer: :erlang.start_timer(@refresh_after, self(), :refresh)}

  defp schedule_refresh(state), do: state

  defp save(%{changed?: false} = state), do: state

  defp save(state) do
    case quietly(state, fn -> Rooms.save(state.room.code, state.room, state.closes_at) end) do
      :ok -> %{state | changed?: false}
      :failed -> unsaved(state)
    end
  end

  defp quietly(state, write) do
    write.()
  rescue
    error -> failed(state, Exception.message(error))
  catch
    :exit, reason -> failed(state, inspect(reason))
  end

  defp failed(state, why) do
    Logger.warning("Room #{state.room.code} could not write its save: #{why}")
    :failed
  end

  defp schedule_close(%{joined: joined, close_timer: nil} = state) when joined == %{} do
    now = DateTime.utc_now()
    state = put_closes_at(state, deadline(state, now))
    wait = max(DateTime.diff(state.closes_at, now, :millisecond), 0)
    %{state | close_timer: :erlang.start_timer(wait, self(), :close)}
  end

  defp schedule_close(state), do: state

  defp deadline(state, now), do: state.closes_at || DateTime.add(now, @close_after, :millisecond)

  defp put_closes_at(%{closes_at: closes_at} = state, closes_at), do: state
  defp put_closes_at(state, closes_at), do: unsaved(%{state | closes_at: closes_at})

  defp unsaved(%{save_timer: nil} = state),
    do: %{state | changed?: true, save_timer: Process.send_after(self(), :save, @save_after)}

  defp unsaved(state), do: %{state | changed?: true}

  defp open(creator),
    do: Registry.count_select(ThreeSixes.Rooms.Registry, [{{:_, :_, creator}, [], [true]}])

  defp tell_removed(state, room) do
    for {pid, id} <- state.joined,
        Room.member?(state.room, id),
        not Room.member?(room, id),
        do: send(pid, :removed)

    state
  end

  defp stop_reveal(%{room: %{game: nil}} = state) do
    Enum.each(state.reveal_timers, &Process.cancel_timer/1)
    %{state | reveal_timers: []}
  end

  defp stop_reveal(state), do: state

  defp move_seat(room, nil, _to), do: {:ok, room}

  defp move_seat(room, from, to) do
    case Room.move_seat(room, from, to) do
      {:roll, room} -> {:ok, roll(room)}
      moved_or_not -> moved_or_not
    end
  end

  defp connected(state), do: state.joined |> Map.values() |> Enum.uniq() |> Dice.shuffle()

  defp roll(room) do
    dice = Map.new(Game.to_roll(room.game), fn {seat, count} -> {seat, Dice.roll(count)} end)
    Room.start_round(room, dice)
  end

  defp changed_if_new(%{room: room} = state, room), do: state
  defp changed_if_new(state, room), do: changed(state, room)

  defp changed(state, room) do
    record(Room.finished(state.room, room))
    state = unsaved(%{state | room: room})
    send_views(state)
    state
  end

  defp record(nil), do: :ok

  defp record(game) do
    case Records.record_game(game) do
      {:ok, _record} -> :ok
      {:error, changeset} -> not_recorded(game, inspect(traverse_errors(changeset)))
    end
  catch
    kind, reason -> not_recorded(game, Exception.format(kind, reason, __STACKTRACE__))
  end

  defp traverse_errors(changeset),
    do: Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)

  defp not_recorded(game, reason),
    do: Logger.error("Game in Room #{game.room_code} not recorded: #{reason}")

  defp send_views(state) do
    for {pid, person_id} <- state.joined do
      send(pid, {:room_view, Room.view_for(state.room, person_id)})
    end
  end
end
