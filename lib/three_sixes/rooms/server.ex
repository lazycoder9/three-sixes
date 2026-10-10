defmodule ThreeSixes.Rooms.Server do
  use GenServer, restart: :temporary

  alias ThreeSixes.Dice
  alias ThreeSixes.Game
  alias ThreeSixes.Room

  @close_after :timer.minutes(15)
  @open_per_guest 5
  @open_per_address 20

  @spec start_link({String.t(), Room.person_id(), String.t(), [pid()]}) :: GenServer.on_start()
  def start_link({code, host_id, address, callers}) do
    GenServer.start_link(__MODULE__, {code, host_id, address, callers},
      name: {:via, Registry, {ThreeSixes.Rooms.Registry, code, {host_id, address}}}
    )
  end

  @spec via(String.t()) :: GenServer.name()
  def via(code), do: {:via, Registry, {ThreeSixes.Rooms.Registry, code}}

  @impl true
  def init({code, host_id, address, callers}) do
    Process.put(:"$callers", callers)

    if open({host_id, :_}) > @open_per_guest or open({:_, address}) > @open_per_address do
      {:stop, :too_many}
    else
      state = %{room: Room.new(code, host_id), joined: %{}, close_timer: nil, reveal_timers: []}
      {:ok, schedule_close(state)}
    end
  end

  @impl true
  def handle_call({:join, pid, person_id}, _from, state) do
    unless Map.has_key?(state.joined, pid), do: Process.monitor(pid)
    if state.close_timer, do: Process.cancel_timer(state.close_timer)
    state = %{state | joined: Map.put(state.joined, pid, person_id), close_timer: nil}
    {:reply, {:ok, Room.view_for(state.room, person_id)}, state}
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

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, schedule_close(%{state | joined: Map.delete(state.joined, pid)})}
  end

  def handle_info({:timeout, timer, :close}, %{close_timer: timer} = state),
    do: {:stop, :normal, state}

  def handle_info({:timeout, _stale, :close}, state), do: {:noreply, state}

  defp schedule_close(%{joined: joined, close_timer: nil} = state) when joined == %{},
    do: %{state | close_timer: :erlang.start_timer(@close_after, self(), :close)}

  defp schedule_close(state), do: state

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

  defp connected(state), do: state.joined |> Map.values() |> Enum.uniq() |> Dice.shuffle()

  defp roll(room) do
    dice = Map.new(Game.to_roll(room.game), fn {seat, count} -> {seat, Dice.roll(count)} end)
    Room.start_round(room, dice)
  end

  defp changed(state, room) do
    state = %{state | room: room}
    send_views(state)
    state
  end

  defp send_views(state) do
    for {pid, person_id} <- state.joined do
      send(pid, {:room_view, Room.view_for(state.room, person_id)})
    end
  end
end
