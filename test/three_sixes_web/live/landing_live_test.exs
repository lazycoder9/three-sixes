defmodule ThreeSixesWeb.LandingLiveTest do
  use ThreeSixesWeb.ConnCase

  import Phoenix.LiveViewTest

  alias ThreeSixes.Dice.Scripted

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
