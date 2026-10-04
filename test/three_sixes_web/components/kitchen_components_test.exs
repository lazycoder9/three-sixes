defmodule ThreeSixesWeb.KitchenComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import ThreeSixesWeb.KitchenComponents

  @pips %{
    1 => [4],
    2 => [2, 6],
    3 => [2, 4, 6],
    4 => [0, 2, 6, 8],
    5 => [0, 2, 4, 6, 8],
    6 => [0, 2, 3, 5, 6, 8]
  }

  test "a die drills the pips of its face into a 3 by 3 grid" do
    for {face, cells} <- @pips do
      html = render_component(&die/1, face: face)
      assert pip_cells(html, ".die") == [cells], "face #{face}"
    end
  end

  test "a cube carries all six faces" do
    html = render_component(&cube/1, face: 3)

    faces =
      for n <- 1..6 do
        html |> pip_cells(".cube__face.f#{n}") |> hd() |> length()
      end

    assert faces == [1, 2, 3, 4, 5, 6]
  end

  test "a cube turns the face it shows toward the viewer, a full tumble per turn" do
    assert body_style(face: 1) =~ "--rx: 0deg; --ry: 0deg"
    assert body_style(face: 2) =~ "--rx: -90deg; --ry: 0deg"
    assert body_style(face: 6, turns: 1) =~ "--rx: 720deg; --ry: 1260deg"
    assert body_style(face: 3, turns: 2) =~ "--rx: 1440deg; --ry: 2070deg"
  end

  test "a cube can tumble in from another face" do
    assert body_style(face: 6, from: 5) =~ "--from-rx: 90deg; --from-ry: 0deg"
  end

  defp pip_cells(html, selector) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> Enum.map(fn die ->
      die
      |> LazyHTML.query("i")
      |> Enum.with_index()
      |> Enum.filter(fn {pip, _} -> "on" in classes(pip) end)
      |> Enum.map(fn {_, index} -> index end)
    end)
  end

  defp classes(node) do
    node |> LazyHTML.attribute("class") |> List.first("") |> String.split()
  end

  defp body_style(assigns) do
    (&cube/1)
    |> render_component(assigns)
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(".cube__body")
    |> LazyHTML.attribute("style")
    |> hd()
  end
end
