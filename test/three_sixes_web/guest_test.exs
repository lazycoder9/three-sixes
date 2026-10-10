defmodule ThreeSixesWeb.GuestTest do
  use ThreeSixesWeb.ConnCase, async: true

  test "a first visit gets a Guest id, and the same cookie keeps it", %{conn: conn} do
    first = get(conn, ~p"/")
    guest_id = get_session(first, "guest_id")
    assert is_binary(guest_id) and byte_size(guest_id) > 0

    again = first |> recycle() |> get(~p"/")
    assert get_session(again, "guest_id") == guest_id
  end

  test "a Guest gets a live socket id of their own, kept by the same cookie", %{conn: conn} do
    first = get(conn, ~p"/")
    live_socket_id = get_session(first, "live_socket_id")
    assert "guest_session:" <> _ = live_socket_id

    assert first |> recycle() |> get(~p"/") |> get_session("live_socket_id") == live_socket_id
    assert build_conn() |> get(~p"/") |> get_session("live_socket_id") != live_socket_id
  end

  test "a session that already has a live socket id keeps it", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{"guest_id" => "g1", "live_socket_id" => "account_session:a1"})
      |> get(~p"/")

    assert get_session(conn, "live_socket_id") == "account_session:a1"
  end

  test "two devices are two Guests", %{conn: conn} do
    one = conn |> get(~p"/") |> get_session("guest_id")
    other = build_conn() |> get(~p"/") |> get_session("guest_id")
    assert one != other
  end
end
