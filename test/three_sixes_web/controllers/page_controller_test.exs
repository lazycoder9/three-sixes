defmodule ThreeSixesWeb.PageControllerTest do
  use ThreeSixesWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Three Sixes"
  end
end
