defmodule ThreeSixes.Rooms.Server do
  use GenServer, restart: :temporary

  alias ThreeSixes.Room

  @spec start_link({String.t(), Room.person_id()}) :: GenServer.on_start()
  def start_link({code, host_id}),
    do: GenServer.start_link(__MODULE__, {code, host_id}, name: via(code))

  @spec via(String.t()) :: GenServer.name()
  def via(code), do: {:via, Registry, {ThreeSixes.Rooms.Registry, code}}

  @impl true
  def init({code, host_id}), do: {:ok, %{room: Room.new(code, host_id), joined: %{}}}

  @impl true
  def handle_call({:join, pid, person_id}, _from, state) do
    unless Map.has_key?(state.joined, pid), do: Process.monitor(pid)
    joined = Map.put(state.joined, pid, person_id)
    {:reply, {:ok, Room.view_for(state.room, person_id)}, %{state | joined: joined}}
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
    {:noreply, %{state | joined: Map.delete(state.joined, pid)}}
  end

  defp send_views(state) do
    for {pid, person_id} <- state.joined do
      send(pid, {:room_view, Room.view_for(state.room, person_id)})
    end
  end
end
