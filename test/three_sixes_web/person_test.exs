defmodule ThreeSixesWeb.PersonTest do
  use ThreeSixesWeb.ConnCase, async: false

  alias ThreeSixes.Accounts

  @connect_info %{x_headers: [], peer_data: %{address: {127, 0, 0, 1}, port: 4000, ssl_cert: nil}}

  test "a session with only a Guest id is that Guest" do
    socket = mount_with(%{"guest_id" => "g"}, @connect_info)

    assert socket.assigns.person_id == "guest:g"
    assert socket.assigns.account == nil
  end

  test "a signed-in session is the Account, whatever Guest id the device holds" do
    {:created, account} = Accounts.find_or_create_dev("Dana")

    socket = mount_with(%{"guest_id" => "g", "account_id" => account.id}, @connect_info)

    assert socket.assigns.person_id == "account:#{account.id}"
    assert socket.assigns.account.id == account.id
    assert socket.assigns.account.nickname == "Dana"
  end

  test "a session naming an Account that is gone is the device's Guest" do
    socket = mount_with(%{"guest_id" => "g", "account_id" => -1}, @connect_info)

    assert socket.assigns.person_id == "guest:g"
    assert socket.assigns.account == nil
  end

  describe "the address a Room is counted against" do
    test "is the right-most x-forwarded-for entry, the one the deploy proxy adds" do
      socket =
        mount_with(%{"guest_id" => "g"}, %{
          x_headers: [{"x-forwarded-for", "10.0.0.1, 203.0.113.7"}],
          peer_data: %{address: {172, 17, 0, 2}, port: 4000, ssl_cert: nil}
        })

      assert socket.assigns.client_address == "203.0.113.7"
    end

    test "is the peer address with no x-forwarded-for" do
      socket =
        mount_with(%{"guest_id" => "g"}, %{
          x_headers: [{"x-request-id", "abc"}],
          peer_data: %{address: {198, 51, 100, 4}, port: 4000, ssl_cert: nil}
        })

      assert socket.assigns.client_address == "198.51.100.4"
    end
  end

  defp mount_with(session, connect_info) do
    socket = %Phoenix.LiveView.Socket{private: %{connect_info: connect_info}}
    {:cont, socket} = ThreeSixesWeb.Person.on_mount(:default, %{}, session, socket)
    socket
  end
end
