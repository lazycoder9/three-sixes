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

  describe "the address a Room is counted against" do
    test "is the right-most x-forwarded-for entry, the one the deploy proxy adds" do
      socket =
        mount_with(%{
          x_headers: [{"x-forwarded-for", "10.0.0.1, 203.0.113.7"}],
          peer_data: %{address: {172, 17, 0, 2}, port: 4000, ssl_cert: nil}
        })

      assert socket.assigns.client_address == "203.0.113.7"
    end

    test "is the peer address with no x-forwarded-for" do
      socket =
        mount_with(%{
          x_headers: [{"x-request-id", "abc"}],
          peer_data: %{address: {198, 51, 100, 4}, port: 4000, ssl_cert: nil}
        })

      assert socket.assigns.client_address == "198.51.100.4"
    end
  end

  defp mount_with(connect_info) do
    socket = %Phoenix.LiveView.Socket{private: %{connect_info: connect_info}}
    {:cont, socket} = ThreeSixesWeb.Guest.on_mount(:default, %{}, %{"guest_id" => "g"}, socket)
    socket
  end
end
