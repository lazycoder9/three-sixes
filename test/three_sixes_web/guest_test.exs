defmodule ThreeSixesWeb.GuestTest do
  use ThreeSixesWeb.ConnCase, async: true

  test "a first visit gets a Guest id, and the same cookie keeps it", %{conn: conn} do
    first = get(conn, ~p"/")
    guest_id = get_session(first, "guest_id")
    assert is_binary(guest_id) and byte_size(guest_id) > 0

    again = first |> recycle() |> get(~p"/")
    assert get_session(again, "guest_id") == guest_id
  end

  test "two devices are two Guests", %{conn: conn} do
    one = conn |> get(~p"/") |> get_session("guest_id")
    other = build_conn() |> get(~p"/") |> get_session("guest_id")
    assert one != other
  end
end
