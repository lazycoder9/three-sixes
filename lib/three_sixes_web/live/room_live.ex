defmodule ThreeSixesWeb.RoomLive do
  use ThreeSixesWeb, :live_view

  alias ThreeSixes.RoomCode
  alias ThreeSixes.Rooms

  @token_colors [:tomato, :teal, :ochre, :walnut]
  # Past this many people, room.css stops zooming the lobby up so the list stays in the window.
  @fits_zoomed 16

  @impl true
  def mount(%{"code" => code}, _session, socket) do
    normal = RoomCode.normalize(code)

    if normal != code and RoomCode.valid?(normal) do
      {:ok, push_navigate(socket, to: ~p"/r/#{normal}", replace: true)}
    else
      {:ok, mount_room(socket, code)}
    end
  end

  defp mount_room(socket, code) do
    socket =
      assign(socket,
        code: code,
        view: nil,
        closed?: false,
        room_ref: nil,
        nickname: "",
        edited?: false,
        wanted: nil,
        held: nil,
        suggestion: nil,
        error: nil
      )

    if connected?(socket) do
      socket
      |> assign(nickname: get_connect_params(socket)["nickname"] || "")
      |> join()
    else
      assign(socket, closed?: Rooms.whereis(code) == nil)
    end
  end

  defp join(socket) do
    %{code: code, person_id: person_id} = socket.assigns

    with {:ok, view} <- Rooms.join(code, person_id),
         pid when is_pid(pid) <- Rooms.whereis(code) do
      assign(socket, view: view, room_ref: Process.monitor(pid))
    else
      _closed -> assign(socket, view: nil, closed?: true)
    end
  end

  @impl true
  def handle_event("create", _params, socket) do
    {:ok, code} = Rooms.create(socket.assigns.person_id)
    {:noreply, push_navigate(socket, to: ~p"/r/#{code}")}
  end

  def handle_event("enter", %{"nickname" => nickname}, socket) do
    socket = assign(socket, nickname: nickname, wanted: String.trim(nickname))
    {:noreply, enter(socket, nickname)}
  end

  def handle_event("join_as", _params, socket),
    do: {:noreply, enter(socket, socket.assigns.suggestion)}

  def handle_event("edit", _params, socket) do
    {:noreply,
     assign(socket, nickname: socket.assigns.suggestion, suggestion: nil, edited?: true)}
  end

  defp enter(socket, nickname) do
    case Rooms.enter(socket.assigns.code, socket.assigns.person_id, nickname) do
      {:ok, view} ->
        socket
        |> assign(view: view, suggestion: nil, error: nil)
        |> push_event("remember-nickname", %{nickname: socket.assigns.wanted})

      {:taken, held, suggestion} ->
        assign(socket, held: held, suggestion: suggestion, error: nil)

      {:error, :blank} ->
        assign(socket, suggestion: nil, error: "Pick a Nickname first.")

      {:error, :too_long} ->
        assign(socket, suggestion: nil, error: "A Nickname is 16 characters at most.")

      {:error, :full} ->
        assign(socket, suggestion: nil, error: "This Room is full.")
    end
  end

  @impl true
  def handle_info({:room_view, view}, socket), do: {:noreply, assign(socket, view: view)}

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{assigns: %{room_ref: ref}} = socket),
    do: {:noreply, join(socket)}

  @impl true
  def render(%{view: %{me: me}} = assigns) when is_binary(me) do
    ~H"""
    <Layouts.room flash={@flash} code={@view.code}>
      <.lobby view={@view} />
    </Layouts.room>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.closed :if={@closed?} />
      <section :if={!@closed?} class="screen screen--narrow">
        <.notebook_page>
          <.room_code :if={!@view} code={@code} />
          <.taken
            :if={@view && @suggestion}
            held={@held}
            suggestion={@suggestion}
          />
          <.join_step
            :if={@view && !@suggestion}
            view={@view}
            nickname={@nickname}
            edited?={@edited?}
            error={@error}
          />
        </.notebook_page>
      </section>
    </Layouts.app>
    """
  end

  defp closed(assigns) do
    ~H"""
    <section class="screen screen--narrow">
      <div class="tiles gone" aria-hidden="true">
        <.letter_tile :for={letter <- ~w(G O N E)} letter={letter} blank />
      </div>
      <.notebook_page>
        <h1>This room has closed.</h1>
        <p>
          A Room closes after 15 minutes with nobody in it. Ask your friends for the new code, or open one yourself.
        </p>
        <div class="row">
          <.block variant={:tomato} phx-click="create">Create a Room</.block>
          <.link navigate={~p"/"} class="block">Enter another code</.link>
        </div>
      </.notebook_page>
    </section>
    """
  end

  attr :view, :map, required: true
  attr :nickname, :string, required: true
  attr :edited?, :boolean, required: true
  attr :error, :string, required: true

  defp join_step(assigns) do
    ~H"""
    <p :if={@view.host?} class="faint">your Room is open</p>
    <p :if={!@view.host?} class="faint">you're joining Room</p>
    <.room_code code={@view.code} />
    <p class="who">
      <.token
        :for={person <- @view.people}
        initial={initial(person.nickname)}
        color={token_color(person.n)}
      />
      <span>{who_is_in(@view)}</span>
    </p>
    <form id="join-form" phx-submit="enter">
      <.write_on_line
        id="nickname"
        name="nickname"
        label="Your Nickname"
        value={@nickname}
        maxlength="16"
        autocomplete="nickname"
        placeholder="write it here"
        error={@error}
        phx-mounted={@edited? && JS.focus()}
      />
      <div class="gap"></div>
      <.block type="submit" variant={:tomato} size={:big} wide>Join Room</.block>
    </form>
    """
  end

  attr :code, :string, required: true

  defp room_code(assigns) do
    ~H"""
    <div id="room-code" class="tiles room-code" aria-label="Room code">
      <.letter_tile :for={letter <- String.graphemes(@code)} letter={letter} />
    </div>
    """
  end

  attr :held, :string, required: true
  attr :suggestion, :string, required: true

  defp taken(assigns) do
    ~H"""
    <p class="faint">there's already a {@held} in this Room</p>
    <h1>
      You're<s aria-hidden="true" data-nickname={@held}></s> <span class="hl">{@suggestion}</span>
      here.
    </h1>
    <div class="row">
      <.block variant={:tomato} phx-click="join_as">Join as {@suggestion}</.block>
      <.block phx-click="edit">Edit</.block>
    </div>
    """
  end

  attr :view, :map, required: true

  defp lobby(assigns) do
    ~H"""
    <div id="lobby" class={["lobby", crowded?(@view) && "lobby--crowded"]}>
      <.notebook_page>
        <h1>Who's playing</h1>
        <ul id="people" class="people">
          <li :for={person <- @view.people} id={"person-#{person.n}"}>
            <.token initial={initial(person.nickname)} color={token_color(person.n)} />
            <span class="people__name">
              {if person.me?, do: "You", else: person.nickname}
              <span :if={person.host?} class="host-tag">Host</span>
            </span>
          </li>
        </ul>
      </.notebook_page>
      <div class="lobby__side">
        <div>
          <p class="lobby__label">Room code</p>
          <div class="tiles">
            <.letter_tile :for={letter <- String.graphemes(@view.code)} letter={letter} />
          </div>
        </div>
        <Layouts.copy_room_link id="lobby-copied" code={@view.code} />
      </div>
    </div>
    """
  end

  defp who_is_in(%{people: [], host?: true}), do: "Nobody else is here yet. You're the Host."
  defp who_is_in(%{people: []}), do: "Nobody is here yet."
  defp who_is_in(%{people: [person]}), do: "#{person.nickname} is in this Room."

  defp who_is_in(%{people: people}) do
    {others, [last]} = people |> Enum.map(& &1.nickname) |> Enum.split(-1)
    "#{Enum.join(others, ", ")} and #{last} are in this Room."
  end

  defp crowded?(view), do: length(view.people) > @fits_zoomed

  defp initial(nickname), do: nickname |> String.first() |> String.upcase()

  defp token_color(n), do: Enum.at(@token_colors, rem(n - 1, length(@token_colors)))
end
