defmodule ThreeSixesWeb.LandingLiveTest do
  use ThreeSixesWeb.ConnCase

  import Phoenix.LiveViewTest

  alias ThreeSixes.Dice.Scripted
  alias ThreeSixes.Rooms

  test "the landing page pitches the game and lands its dice on three sixes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, ~s(header a[aria-label="Three Sixes, home"] .die))
    assert has_element?(view, "h1", "Roll in secret.")
    assert has_element?(view, "h1", "Lie out loud.")

    assert has_element?(
             view,
             "p",
             "Three Sixes is a dice-bluffing game for a Room of friends."
           )

    assert has_element?(view, "button", "Create a Room")
    assert has_element?(view, "fieldset legend", "Join with a code")
    assert length(select(view, "fieldset input.letter-tile")) == 4

    assert faces(view) == ~w(6 6 6)
    assert caption(view) == "Three sixes. The Bid this game is named after."

    assert view |> select("ol.rules > li b") |> Enum.map(&LazyHTML.text/1) ==
             ["Roll in secret", "Bid, or Raise", "Check"]
  end

  test "tapping the dice rolls them and reads the roll back as a Bid", %{conn: conn} do
    Scripted.script([[2, 5, 5], [6, 6, 6]])
    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("#dice") |> render_click()
    assert faces(view) == ~w(2 5 5)
    assert caption(view) == "Two fives. You could say three."

    view |> element("#dice") |> render_click()
    assert faces(view) == ~w(6 6 6)
    assert caption(view) == "Three sixes. For real this time!"
  end

  test "Create a Room opens a Room and lands on its join step as the Host", %{conn: conn} do
    conn = init_test_session(conn, %{"guest_id" => "timur"})
    {:ok, view, _html} = live(conn, ~p"/")

    {:ok, room, _html} =
      view |> element("button", "Create a Room") |> render_click() |> follow_redirect(conn)

    assert has_element?(room, "p", "your Room is open")
  end

  test "Create a Room with every Room open says so and stays on the page", %{conn: conn} do
    fill_every_room()
    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("button", "Create a Room") |> render_click()

    assert has_element?(
             view,
             "#flash-error",
             "Every Room is busy right now. Try again in a few minutes."
           )

    assert has_element?(view, "button", "Create a Room")
  end

  describe "Join with a code" do
    test "fewer than four letters is refused above the tiles", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> form("#join-code", %{code: ["k", "q", "x", ""]}) |> render_submit()

      assert has_element?(
               view,
               "#join-code legend + [role=alert]",
               "A Room code is four letters."
             )

      assert has_element?(view, "#join-code [role=alert] + #code-tiles")
    end

    test "four letters, in any case, go to that Room", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert {:error, {:live_redirect, %{to: "/r/KQXT"}}} =
               view |> form("#join-code", %{code: ["k", "Q", "x", "t"]}) |> render_submit()
    end
  end

  defp fill_every_room do
    %{active: open} = DynamicSupervisor.count_children(ThreeSixes.Rooms.Supervisor)

    for _room <- open..(Application.fetch_env!(:three_sixes, :max_rooms) - 1)//1 do
      {:ok, code} = Rooms.create("guest:host")
      pid = Rooms.whereis(code)
      on_exit(fn -> DynamicSupervisor.terminate_child(ThreeSixes.Rooms.Supervisor, pid) end)
    end
  end

  defp select(view, selector) do
    view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> Enum.to_list()
  end

  defp faces(view) do
    view |> select("#dice .cube") |> Enum.flat_map(&LazyHTML.attribute(&1, "data-face"))
  end

  defp caption(view) do
    view |> select("#dice-caption") |> Enum.map_join(&LazyHTML.text/1) |> String.trim()
  end
end
