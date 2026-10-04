defmodule ThreeSixesWeb.HealthControllerTest do
  use ThreeSixesWeb.ConnCase, async: true

  test "GET /health answers 200 with OK", %{conn: conn} do
    conn = get(conn, ~p"/health")

    assert response(conn, 200) == "OK"
  end
end
