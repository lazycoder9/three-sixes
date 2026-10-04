defmodule ThreeSixes.Rooms.Server do
  use GenServer, restart: :temporary

  alias ThreeSixes.Room

  @close_after :timer.minutes(15)

  @spec start_link({String.t(), Room.person_id()}) :: GenServer.on_start()
  def start_link({code, host_id}),
    do: GenServer.start_link(__MODULE__, {code, host_id}, name: via(code))

  @spec via(String.t()) :: GenServer.name()
  def via(code), do: {:via, Registry, {ThreeSixes.Rooms.Registry, code}}

  @impl true
  def init({code, host_id}) do
    {:ok, schedule_close(%{room: Room.new(code, host_id), joined: %{}, close_timer: nil})}
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
        state = %{state | room: room}
        send_views(state)
        {:reply, {:ok, Room.view_for(room, person_id)}, state}

      refused ->
        {:reply, refused, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, schedule_close(%{state | joined: Map.delete(state.joined, pid)})}
  end

  def handle_info({:timeout, timer, :close}, %{close_timer: timer} = state),
    do: {:stop, :normal, state}

  def handle_info({:timeout, _stale, :close}, state), do: {:noreply, state}

  defp schedule_close(%{joined: joined, close_timer: nil} = state) when joined == %{},
    do: %{state | close_timer: :erlang.start_timer(@close_after, self(), :close)}

  defp schedule_close(state), do: state

  defp send_views(state) do
    for {pid, person_id} <- state.joined do
      send(pid, {:room_view, Room.view_for(state.room, person_id)})
    end
  end
end
