defmodule ThreeSixesWeb.RoomLiveTest do
  use ThreeSixesWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ThreeSixes.Rooms

  test "the Host's join step shows the Room code and that nobody else is here", %{conn: conn} do
    {:ok, code} = Rooms.create("guest:timur")

    {:ok, view, _html} = live(guest(conn, "timur"), ~p"/r/#{code}")

    assert has_element?(view, "p", "your Room is open")
    assert code_tiles(view) == String.graphemes(code)
    assert has_element?(view, "p", "Nobody else is here yet. You're the Host.")
    assert has_element?(view, "button", "Join Room")
  end

  test "two people join one Room and each sees the other appear", %{conn: conn} do
    {:ok, code} = Rooms.create("guest:timur")
    {:ok, timur, _html} = live(guest(conn, "timur"), ~p"/r/#{code}")
    {:ok, dana, _html} = live(guest(build_conn(), "dana"), ~p"/r/#{code}")

    assert has_element?(dana, "p", "you're joining Room")
    assert has_element?(dana, "p", "Nobody is here yet.")

    enter(timur, "Timur")
    assert has_element?(timur, "h1", "You're in, Timur.")
    assert has_element?(dana, ".who", "Timur is in this Room.")
    assert has_element?(dana, ".who .token", "T")

    enter(dana, "Dana")
    assert has_element?(dana, "h1", "You're in, Dana.")
    assert people(dana) == ["Timur Host", "Dana"]
    assert people(timur) == ["Timur Host", "Dana"]
  end

  describe "a Nickname already in the Room, regardless of case" do
    setup %{conn: conn} do
      {:ok, code} = Rooms.create("guest:timur")
      {:ok, _view} = Rooms.enter(code, "guest:dana", "Dana")
      {:ok, view, _html} = live(guest(conn, "other"), ~p"/r/#{code}")
      enter(view, "dana")
      %{view: view}
    end

    test "gets the next number, and Join as takes it", %{view: view} do
      assert has_element?(view, "p", "there's already a dana in this Room")
      assert has_element?(view, "h1", "You're Dana 2 here.")

      view |> element("button", "Join as Dana 2") |> render_click()

      assert has_element?(view, "h1", "You're in, Dana 2.")
      assert people(view) == ["Dana", "Dana 2"]
    end

    test "Edit goes back to the form with the number filled in", %{view: view} do
      view |> element("button", "Edit") |> render_click()

      assert has_element?(view, "#nickname[value='Dana 2']")
      refute has_element?(view, "h1", "You're Dana 2 here.")
    end
  end

  test "an empty Nickname is refused under the line", %{conn: conn} do
    {:ok, code} = Rooms.create("guest:timur")
    {:ok, view, _html} = live(guest(conn, "dana"), ~p"/r/#{code}")

    enter(view, "   ")

    assert has_element?(view, "#join-form [role=alert]", "Pick a Nickname first.")
    assert has_element?(view, "#nickname[aria-invalid=true]")
  end

  test "a Nickname over 16 characters is refused, and so is a 31st person", %{conn: conn} do
    {:ok, code} = Rooms.create("guest:timur")
    {:ok, view, _html} = live(guest(conn, "late"), ~p"/r/#{code}")

    enter(view, "Alexandra Kowalsk")
    assert has_element?(view, "#join-form [role=alert]", "A Nickname is 16 characters at most.")

    for n <- 1..30, do: {:ok, _view} = Rooms.enter(code, "guest:#{n}", "Player #{n}")
    enter(view, "Late")
    assert has_element?(view, "#join-form [role=alert]", "This Room is full.")
  end

  test "a code with no open Room shows the closed screen with both ways out", %{conn: conn} do
    {:ok, code} = Rooms.create("guest:timur")
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
    {:ok, code} = Rooms.create("guest:timur")
    {:ok, first, _html} = live(guest(conn, "dana"), ~p"/r/#{code}")
    enter(first, "Dana")

    {:ok, reloaded, _html} = live(guest(build_conn(), "dana"), ~p"/r/#{code}")

    assert has_element?(reloaded, "h1", "You're in, Dana.")
    refute has_element?(reloaded, "#join-form")
  end

  describe "the Nickname remembered on the device" do
    test "fills the line", %{conn: conn} do
      {:ok, code} = Rooms.create("guest:timur")

      {:ok, view, _html} =
        conn
        |> guest("dana")
        |> put_connect_params(%{"nickname" => "Dana"})
        |> live(~p"/r/#{code}")

      assert has_element?(view, "#nickname[value='Dana']")
    end

    test "is the one the person wrote, kept once they are in", %{conn: conn} do
      {:ok, code} = Rooms.create("guest:timur")
      {:ok, _view} = Rooms.enter(code, "guest:other", "Dana")
      {:ok, view, _html} = live(guest(conn, "dana"), ~p"/r/#{code}")

      enter(view, " dana ")
      view |> element("button", "Join as Dana 2") |> render_click()

      assert_push_event(view, "remember-nickname", %{nickname: "dana"})
    end
  end

  test "a Room that stops while someone is in it shows them the closed screen", %{conn: conn} do
    {:ok, code} = Rooms.create("guest:timur")
    {:ok, view, _html} = live(guest(conn, "timur"), ~p"/r/#{code}")
    enter(view, "Timur")

    close(code)

    assert has_element?(view, "h1", "This room has closed.")
  end

  test "a code written in lowercase goes to the Room's own address", %{conn: conn} do
    {:ok, code} = Rooms.create("guest:timur")

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

  defp guest(conn, guest_id), do: init_test_session(conn, %{"guest_id" => guest_id})

  defp code_tiles(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("[aria-label='Room code'] .letter-tile")
    |> Enum.map(&LazyHTML.text/1)
  end
end
