defmodule ThreeSixesWeb.LayoutsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  test "every notice can be dismissed with a button" do
    html =
      render_component(&ThreeSixesWeb.Layouts.flash_group/1,
        flash: %{"info" => "Saved.", "error" => "Not saved."}
      )

    notices = html |> LazyHTML.from_fragment() |> LazyHTML.query("[role=alert]") |> Enum.to_list()

    assert Enum.map(notices, &LazyHTML.attribute(&1, "id")) ==
             [["flash-info"], ["flash-error"], ["client-error"], ["server-error"]]

    for notice <- notices do
      assert notice
             |> LazyHTML.query(~s(button[type="button"][aria-label="Dismiss"]))
             |> Enum.count() == 1
    end
  end
end
