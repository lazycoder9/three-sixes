defmodule ThreeSixesWeb.SignInRoomLiveTest do
  use ThreeSixesWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ThreeSixes.Accounts
  alias ThreeSixes.Dice.Scripted
  alias ThreeSixes.RoomCode
  alias ThreeSixes.Rooms

  setup do
    on_exit(fn ->
      for {_id, pid, _type, _modules} <-
            DynamicSupervisor.which_children(ThreeSixes.Rooms.Supervisor),
          do: DynamicSupervisor.terminate_child(ThreeSixes.Rooms.Supervisor, pid)
    end)
  end

  describe "a Guest mid-Game signing in" do
    test "on their turn keeps their seat and dice, and plays on as the Account" do
      %{timur: {_, timur}, dana: {dana_conn, dana}, code: code} = table(~w(Timur Dana))
      start(timur, [[3], [5]])
      press(timur, "Bid one five")

      close(dana, code)

      assert text(timur, "#banners") ==
               "Dana is on turn and away 0:00. The table waits. Remove Dana"

      {_, dana} = sign_in(dana_conn, code, "Scully")

      assert faces(dana) == [5]
      assert text(dana, "#my-page .my-page__head") == "Your turn. Raise it, or Check it."
      assert text(dana, "#seat-1 .seat__name") == "Timur"
      refute has_element?(dana, "#seat-2")
      assert text(timur, "#seat-2 .seat__name") == "Dana"
      refute has_element?(timur, ".is-away")
      refute has_element?(timur, "#banners")

      press(dana, "Raise to two fives")

      assert text(timur, "#scrap") == "Dana bids 2 × 2 dice on the table"
      assert text(timur, "#my-page .my-page__head") == "Your turn. Raise it, or Check it."
    end
  end

  describe "a Guest signing in as an Account that already has a seat" do
    test "leaves the Guest's seat, Knocked out mid-Game, and the Account keeps its own" do
      %{timur: {_, timur}, dana: {dana_conn, dana}, code: code} = table(~w(Timur Dana))
      {_, scully} = code |> account("Scully") |> enter_as("Scully")
      start(timur, [[3], [5], [2]])
      press(timur, "Bid one five")
      close(dana, code)

      Scripted.script([[4], [6]])
      {_, dana} = sign_in(dana_conn, code, "Scully")

      for view <- [timur, dana, scully] do
        assert has_element?(view, "#seat-2.is-out", "out")
      end

      assert text(timur, "#scrap") ==
               "Dana is out. The Round is voided. Scully opens the Round. 2 dice on the table"

      for view <- [dana, scully] do
        assert faces(view) == [6]
        assert text(view, "#my-page .my-page__head") == "You open. Make a Bid."
        refute has_element?(view, "#seat-3")
      end

      assert text(timur, "#seat-3 .seat__name") == "Scully"
    end
  end

  describe "the creator signing in from the join step" do
    test "comes back as the Host, and the others see it" do
      {:ok, code} = Rooms.create("guest:timur", "127.0.0.1")
      {_, dana} = guest("dana") |> visit(code) |> enter_as("Dana")
      {timur_conn, timur} = visit(guest("timur"), code)

      assert has_element?(
               timur,
               ~s(header.top nav a[href="/signin?return_to=%2Fr%2F#{code}"]),
               "Sign in"
             )

      close(timur, code)
      {_, timur} = sign_in(timur_conn, code, "Timur")

      assert text(timur, ".faint") == "your Room is open"
      enter(timur, "Timur")

      assert has_element?(timur, "#lobby button", "Start Game")
      assert text(dana, "#person-2 .people__name") == "Timur Host"
      assert text(dana, ".lobby__wait") == "Waiting for Timur to start the Game."
    end

    test "is offered on the closed screen too" do
      code = RoomCode.random()

      {_, closed} = visit(guest("timur"), code)

      assert has_element?(closed, "h1", "This room has closed.")

      assert has_element?(
               closed,
               ~s(header.top nav a[href="/signin?return_to=%2Fr%2F#{code}"]),
               "Sign in"
             )
    end
  end

  describe "the Guest's other tabs" do
    test "are told to disconnect at sign-in, so they reload as the Account" do
      %{dana: {dana_conn, _}, code: code} = table(~w(Dana))
      guest_session = get_session(dana_conn, "live_socket_id")
      ThreeSixesWeb.Endpoint.subscribe(guest_session)

      {signed_in, _} = sign_in(dana_conn, code, "Scully")

      assert_receive %Phoenix.Socket.Broadcast{topic: ^guest_session, event: "disconnect"}
      assert "guest_session:" <> _ = guest_session
      assert get_session(signed_in, "live_socket_id") != guest_session
    end

    test "still joined as the Guest are sent to the Room again once the Account's page joins" do
      %{dana: {dana_conn, _}, code: code} = table(~w(Dana))
      {_, other_tab} = visit(guest("dana"), code)

      sign_in(dana_conn, code, "Scully")

      assert_redirect(other_tab, ~p"/r/#{code}")
    end
  end

  describe "the Room restarting from a save before the sign-in" do
    test "moves the seat again when the Account rejoins" do
      %{timur: {_, timur}, dana: {dana_conn, dana}, code: code} = table(~w(Timur Dana))
      room = Rooms.whereis(code)
      send(room, :save)
      :sys.get_state(room)
      close(dana, code)
      {_, dana} = sign_in(dana_conn, code, "Scully")

      ref = Process.monitor(room)
      Process.exit(room, :kill)
      assert_receive {:DOWN, ^ref, :process, ^room, :killed}
      code |> restarted(room) |> rejoined(2)

      assert text(dana, "#person-2 .people__name") == "You"
      assert text(timur, "#person-2 .people__name") == "Dana"
      refute has_element?(timur, ".is-away")
    end
  end

  describe "the Nickname" do
    test "in use stays in the Room; a new Account saves it, an existing Account keeps its own" do
      {:created, mulder} = Accounts.find_or_create_dev("Mulder")

      %{timur: {_, timur}, dana: {dana_conn, dana}, malika: {malika_conn, malika}, code: code} =
        table(~w(Timur Dana Malika))

      close(dana, code)
      {dana_conn, dana} = sign_in(dana_conn, code, "Scully")
      close(malika, code)
      {_, _malika} = sign_in(malika_conn, code, "Mulder")

      assert Accounts.get_account(get_session(dana_conn, "account_id")).nickname == "Dana"
      assert Accounts.get_account(mulder.id).nickname == "Mulder"
      assert text(timur, "#person-2 .people__name") == "Dana"
      assert text(timur, "#person-3 .people__name") == "Malika"
      assert text(dana, "#person-2 .people__name") == "You"
    end
  end

  describe "the Room menu" do
    test "offers a Guest Sign in with Google and the dev login, with the turn line only on their turn" do
      %{timur: {_, timur}, dana: {_, dana}, code: code} = table(~w(Timur Dana))
      start(timur, [[3], [5]])
      press(timur, "Bid one five")

      for view <- [timur, dana] do
        assert has_element?(
                 view,
                 ~s(#menu-sign-in a[href="/auth/google?return_to=%2Fr%2F#{code}"]),
                 "Sign in with Google"
               )

        assert text(view, "#menu-sign-in .hint") ==
                 "Doesn't work inside some chat apps? Open in Safari or Chrome."

        assert has_element?(view, ~s(#menu-sign-in form.dev[action="/auth/dev"][method="post"]))
        assert has_element?(view, ~s(#menu-sign-in .dev input[name="name"][value="Dana"]))

        assert has_element?(
                 view,
                 ~s(#menu-sign-in .dev input[type="hidden"][name="return_to"][value="/r/#{code}"])
               )
      end

      assert has_element?(dana, "#menu-sign-in", "The table will wait while you sign in.")
      refute has_element?(timur, "#menu-sign-in", "The table will wait")

      press(dana, "Raise to two fives")

      assert has_element?(timur, "#menu-sign-in", "The table will wait while you sign in.")
      refute has_element?(dana, "#menu-sign-in", "The table will wait")
    end

    test "offers a Guest in the lobby sign-in too, and an Account none" do
      %{timur: {_, timur}, code: code} = table(~w(Timur))
      {_, scully} = code |> account("Scully") |> enter_as("Scully")

      assert has_element?(timur, "#room-menu #menu-sign-in", "Sign in with Google")
      refute has_element?(timur, "#menu-sign-in", "The table will wait")
      assert has_element?(scully, "#room-menu")
      refute has_element?(scully, "#menu-sign-in")

      start(timur, [[3], [5]])

      refute has_element?(scully, "#menu-sign-in")
    end

    test "offers only the dev login without Google, and no sign-in with neither" do
      google = Application.fetch_env!(:ueberauth, Ueberauth.Strategy.Google.OAuth)

      on_exit(fn ->
        Application.put_env(:ueberauth, Ueberauth.Strategy.Google.OAuth, google)
        Application.put_env(:three_sixes, :dev_login_enabled, true)
      end)

      Application.put_env(:ueberauth, Ueberauth.Strategy.Google.OAuth, [])
      %{timur: {_, timur}} = table(~w(Timur))

      refute has_element?(timur, ~s(#menu-sign-in a[href^="/auth/google"]))
      refute has_element?(timur, "#menu-sign-in .hint")
      assert has_element?(timur, "#menu-sign-in .dev button", "Dev login")

      Application.put_env(:three_sixes, :dev_login_enabled, false)
      %{timur: {_, timur}} = table(~w(Timur))

      refute has_element?(timur, "#menu-sign-in")
    end
  end

  defp table(nicknames) do
    {:ok, code} = Rooms.create("guest:timur", "127.0.0.1")

    nicknames
    |> Map.new(fn nickname ->
      id = String.downcase(nickname)
      {conn, view} = visit(guest(id), code)
      enter(view, nickname)
      {String.to_existing_atom(id), {conn, view}}
    end)
    |> Map.put(:code, code)
  end

  defp account(code, name) do
    conn = guest(name <> "-phone") |> post(~p"/auth/dev", %{name: name}) |> recycle()
    visit(conn, code)
  end

  defp enter_as({conn, view}, nickname) do
    enter(view, nickname)
    {conn, view}
  end

  defp guest(guest_id), do: build_conn() |> init_test_session(%{"guest_id" => guest_id})

  defp visit(conn, code) do
    conn = get(conn, ~p"/r/#{code}")
    {:ok, view, _html} = live(conn)
    {conn, view}
  end

  defp sign_in(conn, code, name) do
    conn = conn |> recycle() |> post(~p"/auth/dev", %{name: name, return_to: ~p"/r/#{code}"})
    assert redirected_to(conn) == ~p"/r/#{code}"
    conn |> recycle() |> visit(code)
  end

  defp close(view, code) do
    GenServer.stop(view.pid)
    :sys.get_state(Rooms.whereis(code))
  end

  defp restarted(code, old) do
    case Rooms.whereis(code) do
      pid when is_pid(pid) and pid != old ->
        pid

      _old_or_none ->
        Process.sleep(1)
        restarted(code, old)
    end
  end

  defp rejoined(room, seats) do
    if map_size(:sys.get_state(room).joined) < seats do
      Process.sleep(1)
      rejoined(room, seats)
    end
  end

  defp start(host, rolls) do
    Scripted.script(rolls)
    host |> element("#lobby button", "Start Game") |> render_click()
  end

  defp enter(view, nickname) do
    view |> form("#join-form", %{nickname: nickname}) |> render_submit()
  end

  defp press(view, label),
    do: view |> element("#my-page button[aria-label='#{label}']") |> render_click()

  defp text(view, selector) do
    view
    |> render()
    |> String.replace("<", " <")
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> LazyHTML.text()
    |> String.split()
    |> Enum.join(" ")
  end

  defp faces(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#my-page [data-face]")
    |> LazyHTML.attribute("data-face")
    |> Enum.map(&String.to_integer/1)
  end
end
