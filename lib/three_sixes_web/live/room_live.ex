defmodule ThreeSixesWeb.RoomLive do
  use ThreeSixesWeb, :live_view

  import ThreeSixesWeb.TableComponents

  alias ThreeSixes.Accounts
  alias ThreeSixes.Game
  alias ThreeSixes.RoomCode
  alias ThreeSixes.Rooms

  @fits_zoomed 16
  @reaction_wait 2000
  @reaction_shown 3000

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
        rolled: nil,
        spectators_open?: false,
        reactions: %{},
        reactions_seen: 0,
        reaction_wait: nil
      )

    if connected?(socket) do
      socket
      |> assign(nickname: first_nickname(socket))
      |> join()
    else
      assign(socket, closed?: not Rooms.open?(code))
    end
  end

  defp first_nickname(%{assigns: %{account: %{nickname: nickname}}}) when is_binary(nickname),
    do: nickname

  defp first_nickname(socket), do: get_connect_params(socket)["nickname"] || ""

  defp join(socket) do
    %{code: code, person_id: person_id} = socket.assigns

    with {:ok, view} <- Rooms.join(code, person_id),
         pid when is_pid(pid) <- Rooms.whereis(code) do
      socket |> assign(step: 0) |> put_view(view) |> assign(room_ref: Process.monitor(pid))
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

  def handle_event("sit_out", %{"sitting_out" => flag}, socket) when flag in ~w(true false) do
    Rooms.sit_out(socket.assigns.code, socket.assigns.person_id, flag == "true")
    {:noreply, socket}
  end

  def handle_event("spectators", _params, socket),
    do: {:noreply, update(socket, :spectators_open?, &(!&1))}

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

  def handle_event(
        "key",
        %{"key" => key},
        %{assigns: %{view: %{game: %{my_turn?: true} = game}}} = socket
      ),
      do: {:noreply, play_key(socket, game, key)}

  def handle_event("remove", %{"n" => n}, socket) do
    with {:ok, n} <- whole(n), do: Rooms.remove(socket.assigns.code, socket.assigns.person_id, n)
    {:noreply, socket}
  end

  def handle_event("leave", _params, socket) do
    Rooms.leave(socket.assigns.code, socket.assigns.person_id)

    {:noreply,
     socket
     |> put_flash(:info, "You left Room #{socket.assigns.code}.")
     |> push_navigate(to: ~p"/")}
  end

  def handle_event("make_host", %{"n" => n}, socket) do
    with {:ok, n} <- whole(n),
         do: Rooms.make_host(socket.assigns.code, socket.assigns.person_id, n)

    {:noreply, socket}
  end

  def handle_event("react", %{"reaction" => key}, socket) when is_binary(key) do
    case Rooms.react(socket.assigns.code, socket.assigns.person_id, key) do
      :ok ->
        wait = make_ref()
        Process.send_after(self(), {:reaction_wait_over, wait}, @reaction_wait)
        {:noreply, assign(socket, reaction_wait: wait)}

      _refused ->
        {:noreply, socket}
    end
  end

  def handle_event(event, _params, socket) when event in ~w(raise step sit_out key react),
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

  @face_keys ~w(1 2 3 4 5 6)

  defp play_key(socket, game, key) when key in @face_keys do
    %{code: code, person_id: person_id, step: step} = socket.assigns
    face = String.to_integer(key)

    with {count, face} <- Game.cheapest_offer(game.bid, game.dice_on_table, step, face),
         do: Rooms.raise(code, person_id, count, face)

    socket
  end

  defp play_key(socket, game, key) when key in ~w(ArrowRight +),
    do: assign(socket, step: clamp_step(game, socket.assigns.step + 1))

  defp play_key(socket, game, key) when key in ~w(ArrowLeft -),
    do: assign(socket, step: clamp_step(game, socket.assigns.step - 1))

  defp play_key(socket, _game, key) when key in ~w(c C) do
    Rooms.check(socket.assigns.code, socket.assigns.person_id)
    socket
  end

  defp play_key(socket, _game, _key), do: socket

  defp clamp_step(game, step),
    do: step |> min(Game.max_step(game.bid, game.dice_on_table)) |> max(0)

  @impl true
  def handle_info({:room_view, view}, socket) do
    old = socket.assigns.view
    {:noreply, socket |> put_view(view) |> new_host(old, view)}
  end

  def handle_info(:removed, socket) do
    {:noreply,
     socket
     |> put_flash(:info, removed(socket.assigns.code))
     |> push_navigate(to: ~p"/")}
  end

  def handle_info({:reaction, %{by: by, key: key}}, socket) do
    id = socket.assigns.reactions_seen + 1
    Process.send_after(self(), {:reaction_over, by.n, id}, @reaction_shown)

    {:noreply,
     socket
     |> assign(reactions_seen: id)
     |> update(:reactions, &Map.put(&1, by.n, %{by: by, key: key, id: id}))}
  end

  def handle_info({:reaction_over, n, id}, socket) do
    case socket.assigns.reactions do
      %{^n => %{id: ^id}} -> {:noreply, update(socket, :reactions, &Map.delete(&1, n))}
      _replaced -> {:noreply, socket}
    end
  end

  def handle_info({:reaction_wait_over, wait}, %{assigns: %{reaction_wait: wait}} = socket),
    do: {:noreply, assign(socket, reaction_wait: nil)}

  def handle_info({:reaction_wait_over, _stale}, socket), do: {:noreply, socket}

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{assigns: %{room_ref: ref}} = socket),
    do: {:noreply, join(socket)}

  defp put_view(socket, view) do
    %{view: old, step: step, rolled: rolled} = socket.assigns
    step = if bid_key(view) == bid_key(old), do: step, else: 0
    socket = if view.game, do: socket, else: assign(socket, spectators_open?: false)
    assign(socket, view: view, step: step, rolled: rolled(view, old, rolled))
  end

  @impl true
  def render(%{view: %{me: me, game: %{}}} = assigns) when is_binary(me) do
    ~H"""
    <Layouts.room
      flash={@flash}
      code={@view.code}
      sitting_out?={@view.sitting_out?}
      playing?={@view.playing?}
      revealing?={@view.game.reveal != nil}
    >
      <:under_code :if={@view.spectators != []}>
        <.spectators
          spectators={@view.spectators}
          open?={@spectators_open?}
          tappable={tappable(@view)}
          reactions={@reactions}
        />
      </:under_code>
      <.game_table
        game={@view.game}
        step={@step}
        rolled={@rolled}
        tappable={tappable(@view)}
        reactions={@reactions}
        waiting?={@reaction_wait != nil}
      />
      <.person_dialog :for={person <- tappable_people(@view)} person={person} game={@view.game} />
    </Layouts.room>
    """
  end

  def render(%{view: %{me: me}} = assigns) when is_binary(me) do
    ~H"""
    <Layouts.room
      flash={@flash}
      code={@view.code}
      sitting_out?={@view.sitting_out?}
      playing?={@view.playing?}
    >
      <.lobby view={@view} reactions={@reactions} waiting?={@reaction_wait != nil} />
      <.person_dialog :for={person <- tappable_people(@view)} person={person} />
    </Layouts.room>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} account={@account} return_to={nil}>
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
    <p :if={@view.removed?} id="removed">{removed(@view.code)}</p>
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

  attr :person, :map, required: true
  attr :game, :map, default: nil

  defp person_dialog(assigns) do
    ~H"""
    <div
      id={"person-dialog-#{@person.n}"}
      class="dialog"
      popover
      role="dialog"
      aria-labelledby={"person-dialog-#{@person.n}-title"}
    >
      <h2 id={"person-dialog-#{@person.n}-title"}>{@person.nickname}</h2>
      <div class="stack">
        <.block
          phx-click="make_host"
          phx-value-n={@person.n}
          popovertarget={"person-dialog-#{@person.n}"}
          popovertargetaction="hide"
        >
          Make {@person.nickname} the Host
        </.block>
        <.block
          variant={:walnut}
          phx-click="remove"
          phx-value-n={@person.n}
          popovertarget={"person-dialog-#{@person.n}"}
          popovertargetaction="hide"
        >
          Remove from the Room
        </.block>
      </div>
      <small>
        {if @person.playing?,
          do:
            "Removing a Player mid-Game Knocks them out#{if !@game.reveal, do: " and voids the Round"}."}
        {@person.nickname} can come back with the Room code{if @game, do: ", as a Spectator"}.
      </small>
      <div class="row">
        <.block popovertarget={"person-dialog-#{@person.n}"} popovertargetaction="hide">
          Cancel
        </.block>
      </div>
    </div>
    """
  end

  attr :view, :map, required: true
  attr :reactions, :map, required: true
  attr :waiting?, :boolean, required: true

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
              <.person_tap person={person} tappable={tappable(@view)}>
                <.person_token person={person} />
                <span class="people__name">
                  {if person.me?, do: "You", else: person.nickname}
                  <span :if={person.host?} class="host-tag">Host</span>
                  <.reaction :if={@reactions[person.n]} reaction={@reactions[person.n]} side? />
                  <small :if={person.sitting_out?}>sitting out</small>
                </span>
              </.person_tap>
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
        <form id="sit-out-form" phx-change="sit_out" phx-auto-recover="ignore">
          <label class="tick">
            <input type="hidden" name="sitting_out" value="false" />
            <input type="checkbox" name="sitting_out" value="true" checked={@view.sitting_out?} />
            Sit out the next Game
          </label>
        </form>
        <div :if={@view.host?} class="lobby__start">
          <.block variant={:tomato} size={:big} phx-click="start" disabled={!@view.can_start?}>
            {if @view.over, do: "Next Game", else: "Start Game"}
          </.block>
          <p class="lobby__wait">{dealt_in(@view.dealt_in)}</p>
        </div>
        <p :if={!@view.host?} class="lobby__wait">{waiting_for_host(@view)}</p>
      </div>
      <.reaction_note waiting?={@waiting?} />
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

  defp removed(code),
    do: "You were removed from Room #{code}. You can come back with the Room code."

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

  defp new_host(socket, %{host_nickname: old}, %{host_nickname: new} = view)
       when is_binary(old) and is_binary(new) and old != new,
       do:
         put_flash(
           socket,
           :info,
           if(view.host?, do: "You're the Host now.", else: "#{new} is the Host now.")
         )

  defp new_host(socket, _old, _view), do: socket

  defp rolled(_view, nil, rolled), do: rolled
  defp rolled(%{game: %{round: round}}, %{game: %{round: round}}, rolled), do: rolled

  defp rolled(%{game: %{round: round}}, %{game: %{my_dice: [_ | _] = dice}}, _rolled),
    do: {round, length(dice)}

  defp rolled(%{game: %{round: round}}, _old, _rolled), do: {round, 0}
  defp rolled(_view, _old, _rolled), do: nil

  defp bid_key(%{game: %{round: round, bid: bid}}), do: {round, bid}
  defp bid_key(_view), do: nil

  defp tappable_people(%{host?: true, people: people}), do: Enum.reject(people, & &1.me?)
  defp tappable_people(_view), do: []

  defp tappable(view), do: MapSet.new(tappable_people(view), & &1.n)

  defp crowded?(view), do: length(view.people) > @fits_zoomed
end
