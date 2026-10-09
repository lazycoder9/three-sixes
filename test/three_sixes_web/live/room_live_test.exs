defmodule ThreeSixesWeb.RoomLiveTest do
  use ThreeSixesWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ThreeSixes.Rooms

  setup do
    on_exit(fn ->
      for {_id, pid, _type, _modules} <-
            DynamicSupervisor.which_children(ThreeSixes.Rooms.Supervisor),
          do: DynamicSupervisor.terminate_child(ThreeSixes.Rooms.Supervisor, pid)
    end)
  end

  test "the Host's join step shows the Room code and that nobody else is here", %{conn: conn} do
    {:ok, code} = Rooms.create("guest:timur", "127.0.0.1")

    {:ok, view, _html} = live(guest(conn, "timur"), ~p"/r/#{code}")

    assert has_element?(view, "p", "your Room is open")
    assert code_tiles(view) == String.graphemes(code)
    assert has_element?(view, "p", "Nobody else is here yet. You're the Host.")
    assert has_element?(view, "button", "Join Room")
  end

  test "two people join one Room and each sees the other appear", %{conn: conn} do
    {:ok, code} = Rooms.create("guest:timur", "127.0.0.1")
    {:ok, timur, _html} = live(guest(conn, "timur"), ~p"/r/#{code}")
    {:ok, dana, _html} = live(guest(build_conn(), "dana"), ~p"/r/#{code}")

    assert has_element?(dana, "p", "you're joining Room")
    assert has_element?(dana, "p", "Nobody is here yet.")

    enter(timur, "Timur")
    assert has_element?(timur, "#lobby h1", "Who's playing")
    assert people(timur) == ["T You Host"]
    assert has_element?(dana, ".who", "Timur is in this Room.")
    assert has_element?(dana, ".who .token", "T")

    enter(dana, "Dana")
    assert has_element?(dana, "#lobby h1", "Who's playing")
    assert people(dana) == ["T Timur Host", "D You"]
    assert people(timur) == ["T You Host", "D Dana"]
  end

  test "beside the list are the Room code in tiles and Copy Room link with the Room's address",
       %{conn: conn} do
    {:ok, code} = Rooms.create("guest:timur", "127.0.0.1")
    {:ok, view, _html} = live(guest(conn, "timur"), ~p"/r/#{code}")
    enter(view, "Timur")

    assert has_element?(view, "#lobby p", "Room code")
    assert code_tiles(view, "#lobby") == String.graphemes(code)
    assert copies(view, "#lobby button") == "http://localhost:4002/r/#{code}"
  end

  test "once in, the Room bar shows the logo, the Room code and a menu with Copy Room link and Light or dark",
       %{conn: conn} do
    {:ok, code} = Rooms.create("guest:timur", "127.0.0.1")
    {:ok, view, _html} = live(guest(conn, "timur"), ~p"/r/#{code}")
    assert has_element?(view, "header.top")
    refute has_element?(view, "header.roombar")

    enter(view, "Timur")

    refute has_element?(view, "header.top")
    assert has_element?(view, ~s(header.roombar a[aria-label="Three Sixes, home"] .die))
    assert code_tiles(view, "header.roombar") == String.graphemes(code)

    assert has_element?(
             view,
             ~s(header.roombar button[popovertarget="room-menu"][aria-label="Room menu"])
           )

    assert has_element?(view, "#room-menu[popover] h2", "Room #{code}")
    assert copies(view, "#room-menu button") == "http://localhost:4002/r/#{code}"
    assert has_element?(view, ~s(#room-menu button[phx-hook="ThemeSwitch"]), "Light or dark")

    assert has_element?(
             view,
             ~s(#room-menu button[popovertarget="room-menu"][popovertargetaction="hide"]),
             "Close"
           )
  end

  test "the Room's creator and a joining Guest see no Sign in on the join step", %{conn: conn} do
    {:ok, code} = Rooms.create("guest:timur", "127.0.0.1")
    {:ok, timur, _html} = live(guest(conn, "timur"), ~p"/r/#{code}")
    {:ok, dana, _html} = live(guest(build_conn(), "dana"), ~p"/r/#{code}")

    for view <- [timur, dana] do
      assert has_element?(view, "button", "Join Room")
      assert has_element?(view, "header.top nav #theme-switch")
      refute has_element?(view, "header.top nav a", "Sign in")
    end
  end

  describe "a Nickname already in the Room, regardless of case" do
    setup %{conn: conn} do
      {:ok, code} = Rooms.create("guest:timur", "127.0.0.1")
      {:ok, _view} = Rooms.enter(code, "guest:dana", "Dana")
      {:ok, view, _html} = live(guest(conn, "other"), ~p"/r/#{code}")
      enter(view, "dana")
      %{view: view}
    end

    test "gets the next number, and Join as takes it", %{view: view} do
      assert has_element?(view, "p", "there's already a Dana in this Room")
      assert has_element?(view, "h1 s[data-nickname='Dana']")
      assert has_element?(view, "h1", "You're Dana 2 here.")

      view |> element("button", "Join as Dana 2") |> render_click()

      assert people(view) == ["D Dana", "D You"]
    end

    test "Edit goes back to the form with the number filled in", %{view: view} do
      view |> element("button", "Edit") |> render_click()

      assert has_element?(view, "#nickname[value='Dana 2']")
      refute has_element?(view, "h1", "You're Dana 2 here.")
    end
  end

  test "a Join as with no number offered is ignored and the Room stays open", %{conn: conn} do
    {:ok, code} = Rooms.create("guest:timur", "127.0.0.1")
    {:ok, timur, _html} = live(guest(conn, "timur"), ~p"/r/#{code}")
    enter(timur, "Timur")
    {:ok, dana, _html} = live(guest(build_conn(), "dana"), ~p"/r/#{code}")

    render_click(dana, "join_as")

    assert has_element?(dana, "#join-form")
    assert people(timur) == ["T You Host"]
    enter(dana, "Dana")
    assert people(timur) == ["T You Host", "D Dana"]
  end

  test "an empty Nickname is refused under the line", %{conn: conn} do
    {:ok, code} = Rooms.create("guest:timur", "127.0.0.1")
    {:ok, view, _html} = live(guest(conn, "dana"), ~p"/r/#{code}")

    enter(view, "   ")

    assert has_element?(view, "#join-form [role=alert]", "Pick a Nickname first.")
    assert has_element?(view, "#nickname[aria-invalid=true]")
  end

  test "a Nickname over 16 characters is refused, and so is a 31st person", %{conn: conn} do
    {:ok, code} = Rooms.create("guest:timur", "127.0.0.1")
    {:ok, view, _html} = live(guest(conn, "late"), ~p"/r/#{code}")

    enter(view, "Alexandra Kowalsk")
    assert has_element?(view, "#join-form [role=alert]", "A Nickname is 16 characters at most.")

    for n <- 1..30, do: {:ok, _view} = Rooms.enter(code, "guest:#{n}", "Player #{n}")
    enter(view, "Late")
    assert has_element?(view, "#join-form [role=alert]", "This Room is full.")
  end

  test "a code with no open Room shows the closed screen with both ways out", %{conn: conn} do
    {:ok, code} = Rooms.create("guest:timur", "127.0.0.1")
    close(code)
    conn = guest(conn, "dana")

    {:ok, view, _html} = live(conn, ~p"/r/#{code}")

    assert has_element?(view, "h1", "This room has closed.")
    assert has_element?(view, ~s(a[href="/"]), "Enter another code")

    {:ok, new_room, _html} =
      view |> element("button", "Create a Room") |> render_click() |> follow_redirect(conn)

    assert has_element?(new_room, "p", "your Room is open")
  end

  test "someone already in the Room who reloads goes straight in", %{conn: conn} do
    {:ok, code} = Rooms.create("guest:timur", "127.0.0.1")
    {:ok, first, _html} = live(guest(conn, "dana"), ~p"/r/#{code}")
    enter(first, "Dana")

    {:ok, reloaded, _html} = live(guest(build_conn(), "dana"), ~p"/r/#{code}")

    assert people(reloaded) == ["D You"]
    refute has_element?(reloaded, "#join-form")
  end

  describe "the Nickname remembered on the device" do
    test "fills the line", %{conn: conn} do
      {:ok, code} = Rooms.create("guest:timur", "127.0.0.1")

      {:ok, view, _html} =
        conn
        |> guest("dana")
        |> put_connect_params(%{"nickname" => "Dana"})
        |> live(~p"/r/#{code}")

      assert has_element?(view, "#nickname[value='Dana']")
    end

    test "is the one the person wrote, kept once they are in", %{conn: conn} do
      {:ok, code} = Rooms.create("guest:timur", "127.0.0.1")
      {:ok, _view} = Rooms.enter(code, "guest:other", "Dana")
      {:ok, view, _html} = live(guest(conn, "dana"), ~p"/r/#{code}")

      enter(view, " dana ")
      view |> element("button", "Join as Dana 2") |> render_click()

      assert_push_event(view, "remember-nickname", %{nickname: "dana"})
    end
  end

  describe "an Account" do
    test "finds its saved Nickname on the line, and a changed one is saved for the next Room",
         %{conn: conn} do
      conn = conn |> guest("dana") |> sign_in("Dana")
      {:ok, code} = Rooms.create("guest:timur", "127.0.0.1")

      {:ok, view, _html} =
        conn |> put_connect_params(%{"nickname" => "Guest Dana"}) |> live(~p"/r/#{code}")

      assert has_element?(view, "#nickname[value='Dana']")
      assert has_element?(view, "#join-form .hint", "Filled in from your Account.")

      enter(view, " Dee ")
      assert people(view) == ["D You"]
      refute_push_event(view, "remember-nickname", _payload)

      {:ok, next_code} = Rooms.create("guest:timur", "127.0.0.1")
      {:ok, next, _html} = live(conn, ~p"/r/#{next_code}")

      assert has_element?(next, "#nickname[value='Dee']")
      assert has_element?(next, "#join-form .hint", "Filled in from your Account.")
    end

    test "signed in on two devices is one person in the Room", %{conn: conn} do
      phone = conn |> guest("phone") |> sign_in("Dana")
      laptop = build_conn() |> guest("laptop") |> sign_in("Dana")
      {:ok, code} = Rooms.create("guest:timur", "127.0.0.1")

      {:ok, on_phone, _html} = live(phone, ~p"/r/#{code}")
      enter(on_phone, "Dana")
      {:ok, on_laptop, _html} = live(laptop, ~p"/r/#{code}")

      refute has_element?(on_laptop, "#join-form")
      assert people(on_laptop) == ["D You"]
      assert people(on_phone) == ["D You"]
    end
  end

  test "a Room that stops while someone is in it shows them the closed screen", %{conn: conn} do
    {:ok, code} = Rooms.create("guest:timur", "127.0.0.1")
    {:ok, view, _html} = live(guest(conn, "timur"), ~p"/r/#{code}")
    enter(view, "Timur")

    close(code)

    assert has_element?(view, "h1", "This room has closed.")
  end

  test "a code written in lowercase goes to the Room's own address", %{conn: conn} do
    {:ok, code} = Rooms.create("guest:timur", "127.0.0.1")

    assert {:error, {:live_redirect, %{to: to}}} =
             live(guest(conn, "dana"), "/r/#{String.downcase(code)}")

    assert to == ~p"/r/#{code}"
  end

  test "something that cannot be a Room code shows the closed screen", %{conn: conn} do
    {:ok, view, _html} = live(guest(conn, "dana"), ~p"/r/12")
    assert has_element?(view, "h1", "This room has closed.")
  end

  defp close(code) do
    ref = code |> Rooms.whereis() |> Process.monitor()
    :ok = DynamicSupervisor.terminate_child(ThreeSixes.Rooms.Supervisor, Rooms.whereis(code))
    assert_receive {:DOWN, ^ref, :process, _pid, _reason}
  end

  defp enter(view, nickname) do
    view |> form("#join-form", %{nickname: nickname}) |> render_submit()
  end

  defp people(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#people li")
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.split() |> Enum.join(" ")))
  end

  defp sign_in(conn, name), do: conn |> post(~p"/auth/dev", %{name: name}) |> recycle()

  defp guest(conn, guest_id), do: init_test_session(conn, %{"guest_id" => guest_id})

  defp code_tiles(view, within \\ "[aria-label='Room code']") do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#{within} .letter-tile")
    |> Enum.map(&LazyHTML.text/1)
  end

  defp copies(view, selector) do
    [click] =
      view
      |> element(selector, "Copy Room link")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.attribute("phx-click")

    [["dispatch", %{"event" => "three-sixes:copy", "detail" => %{"text" => text}}]] =
      JSON.decode!(click)

    text
  end
end
