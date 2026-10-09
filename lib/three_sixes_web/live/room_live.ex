defmodule ThreeSixesWeb.RoomLive do
  use ThreeSixesWeb, :live_view

  import ThreeSixesWeb.TableComponents

  alias ThreeSixes.Accounts
  alias ThreeSixes.Game
  alias ThreeSixes.RoomCode
  alias ThreeSixes.Rooms

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
        error: nil,
        step: 0,
        rolled: nil
      )

    if connected?(socket) do
      socket
      |> assign(nickname: first_nickname(socket))
      |> join()
    else
      assign(socket, closed?: Rooms.whereis(code) == nil)
    end
  end

  defp first_nickname(%{assigns: %{account: %{nickname: nickname}}}) when is_binary(nickname),
    do: nickname

  defp first_nickname(socket), do: get_connect_params(socket)["nickname"] || ""

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
    case Rooms.create(socket.assigns.person_id, socket.assigns.client_address) do
      {:ok, code} ->
        {:noreply, push_navigate(socket, to: ~p"/r/#{code}")}

      {:error, :busy} ->
        {:noreply,
         put_flash(socket, :error, "Every Room is busy right now. Try again in a few minutes.")}

      {:error, :too_many} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "You can't open more Rooms right now. Try again in a few minutes."
         )}
    end
  end

  def handle_event("enter", %{"nickname" => nickname}, socket) do
    socket = assign(socket, nickname: nickname, wanted: String.trim(nickname))
    {:noreply, enter(socket, nickname)}
  end

  def handle_event("join_as", _params, %{assigns: %{suggestion: suggestion}} = socket)
      when is_binary(suggestion),
      do: {:noreply, enter(socket, suggestion)}

  def handle_event("join_as", _params, socket), do: {:noreply, socket}

  def handle_event("edit", _params, socket) do
    {:noreply,
     assign(socket, nickname: socket.assigns.suggestion, suggestion: nil, edited?: true)}
  end

  def handle_event("start", _params, socket) do
    Rooms.start_game(socket.assigns.code, socket.assigns.person_id)
    {:noreply, socket}
  end

  def handle_event("raise", %{"count" => count, "face" => face}, socket) do
    with {:ok, count} <- whole(count), {:ok, face} <- whole(face) do
      Rooms.raise(socket.assigns.code, socket.assigns.person_id, count, face)
    end

    {:noreply, socket}
  end

  def handle_event("check", _params, socket) do
    Rooms.check(socket.assigns.code, socket.assigns.person_id)
    {:noreply, socket}
  end

  def handle_event("step", %{"by" => by}, %{assigns: %{view: %{game: %{} = game}}} = socket) do
    case whole(by) do
      {:ok, by} when by in [-1, 1] ->
        {:noreply, assign(socket, step: clamp_step(game, socket.assigns.step + by))}

      _junk ->
        {:noreply, socket}
    end
  end

  def handle_event(event, _params, socket) when event in ~w(raise step),
    do: {:noreply, socket}

  defp enter(socket, nickname) do
    case Rooms.enter(socket.assigns.code, socket.assigns.person_id, nickname) do
      {:ok, view} ->
        socket
        |> assign(view: view, suggestion: nil, error: nil)
        |> remember_nickname()

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

  defp remember_nickname(%{assigns: %{account: nil, wanted: wanted}} = socket),
    do: push_event(socket, "remember-nickname", %{nickname: wanted})

  defp remember_nickname(%{assigns: %{account: %{nickname: wanted}}} = socket)
       when wanted == socket.assigns.wanted,
       do: socket

  defp remember_nickname(%{assigns: %{account: account, wanted: wanted}} = socket) do
    case Accounts.save_nickname(account, wanted) do
      {:ok, account} -> assign(socket, account: account)
      {:error, _changeset} -> socket
    end
  end

  defp from_account?(%{nickname: nickname}, nickname), do: true
  defp from_account?(_account, _nickname), do: false

  defp whole(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> {:ok, integer}
      _junk -> :error
    end
  end

  defp whole(_value), do: :error

  defp clamp_step(game, step) do
    case {more_dice(game, 0), more_dice(game, step)} do
      {%{count: least}, %{count: count}} -> count - least
      _none -> 0
    end
  end

  defp more_dice(game, step),
    do: game.bid |> Game.offers(game.dice_on_table, step) |> Enum.find(&Map.has_key?(&1, :step?))

  @impl true
  def handle_info({:room_view, view}, socket) do
    %{view: old, step: step, rolled: rolled} = socket.assigns
    step = if bid_key(view) == bid_key(old), do: step, else: 0
    {:noreply, assign(socket, view: view, step: step, rolled: rolled(view, old, rolled))}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{assigns: %{room_ref: ref}} = socket),
    do: {:noreply, join(socket)}

  @impl true
  def render(%{view: %{me: me, game: %{}}} = assigns) when is_binary(me) do
    ~H"""
    <Layouts.room flash={@flash} code={@view.code}>
      <.game_table game={@view.game} step={@step} rolled={@rolled} />
    </Layouts.room>
    """
  end

  def render(%{view: %{me: me}} = assigns) when is_binary(me) do
    ~H"""
    <Layouts.room flash={@flash} code={@view.code}>
      <.lobby view={@view} />
    </Layouts.room>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} account={@account} return_to={~p"/r/#{@code}"}>
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
            from_account?={from_account?(@account, @nickname)}
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
  attr :from_account?, :boolean, required: true
  attr :edited?, :boolean, required: true
  attr :error, :string, required: true

  defp join_step(assigns) do
    ~H"""
    <p :if={@view.host?} class="faint">your Room is open</p>
    <p :if={!@view.host?} class="faint">you're joining Room</p>
    <.room_code code={@view.code} />
    <p class="who">
      <.person_token :for={person <- @view.people} person={person} />
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
        hint={@from_account? && "Filled in from your Account."}
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
    <div
      id="lobby"
      class={["lobby", @view.over && "is-over", crowded?(@view) && "lobby--crowded"]}
    >
      <div class="lobby__pages">
        <.placement :if={@view.over} over={@view.over} />
        <.notebook_page>
          <h1>{if @view.over, do: "Next Game", else: "Who's playing"}</h1>
          <ul id="people" class="people">
            <li :for={person <- @view.people} id={"person-#{person.n}"}>
              <.person_token person={person} />
              <span class="people__name">
                {if person.me?, do: "You", else: person.nickname}
                <span :if={person.host?} class="host-tag">Host</span>
              </span>
              <.tally count={person.tally} />
            </li>
          </ul>
        </.notebook_page>
      </div>
      <div class="lobby__side">
        <div>
          <p class="lobby__label">Room code</p>
          <div class="tiles">
            <.letter_tile :for={letter <- String.graphemes(@view.code)} letter={letter} />
          </div>
        </div>
        <Layouts.copy_room_link id="lobby-copied" code={@view.code} />
        <div :if={@view.host?} class="lobby__start">
          <.block variant={:tomato} size={:big} phx-click="start" disabled={!@view.can_start?}>
            {if @view.over, do: "Next Game", else: "Start Game"}
          </.block>
          <p class="lobby__wait">{dealt_in(@view.dealt_in)}</p>
        </div>
        <p :if={!@view.host?} class="lobby__wait">{waiting_for_host(@view)}</p>
      </div>
    </div>
    """
  end

  attr :over, :map, required: true

  defp placement(assigns) do
    ~H"""
    <.notebook_page id="placement">
      <h1>{if @over.winner.me?, do: "You win!", else: "#{@over.winner.nickname} wins."}</h1>
      <p class="faint">Final Placement, after {rounds(@over.rounds)}</p>
      <ol class="placement">
        <li :for={{person, place} <- Enum.with_index(@over.placement, 1)}>
          <.person_token person={person} />
          <span class={place == 1 && "circled"}>
            <span :if={person.me?} class="hl">You</span>{if !person.me?, do: person.nickname}
          </span>
        </li>
      </ol>
    </.notebook_page>
    """
  end

  defp rounds(1), do: "1 Round"
  defp rounds(count), do: "#{count} Rounds"

  defp waiting_for_host(view) do
    host = view.host_nickname || "the Host"
    "Waiting for #{host} to start #{if view.over, do: "the next Game", else: "the Game"}."
  end

  defp dealt_in(count) when count < 2, do: "A Game needs two people."
  defp dealt_in(count), do: "#{count} people are dealt in. Seats are shuffled."

  defp who_is_in(%{people: [], host?: true}), do: "Nobody else is here yet. You're the Host."
  defp who_is_in(%{people: []}), do: "Nobody is here yet."
  defp who_is_in(%{people: [person]}), do: "#{person.nickname} is in this Room."

  defp who_is_in(%{people: people}) do
    {others, [last]} = people |> Enum.map(& &1.nickname) |> Enum.split(-1)
    "#{Enum.join(others, ", ")} and #{last} are in this Room."
  end

  defp rolled(%{game: %{round: round}}, %{game: %{round: round}}, rolled), do: rolled

  defp rolled(%{game: %{round: round}}, %{game: %{my_dice: [_ | _] = dice}}, _rolled),
    do: {round, length(dice)}

  defp rolled(%{game: %{round: round}}, _old, _rolled), do: {round, 0}
  defp rolled(_view, _old, _rolled), do: nil

  defp bid_key(%{game: %{round: round, bid: bid}}), do: {round, bid}
  defp bid_key(_view), do: nil

  defp crowded?(view), do: length(view.people) > @fits_zoomed
end
