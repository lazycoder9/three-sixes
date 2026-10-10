defmodule ThreeSixesWeb.AuthController do
  use ThreeSixesWeb, :controller

  require Logger

  alias ThreeSixes.Accounts
  alias ThreeSixesWeb.Guest

  @control_characters Enum.map([127 | Enum.to_list(0..31)], &<<&1>>)

  plug :store_return_to when action == :request
  plug Ueberauth when action in [:request, :callback]

  def request(conn, _params), do: conn

  def callback(%{assigns: %{ueberauth_failure: failure}} = conn, _params) do
    Logger.info("Google sign-in failed: " <> Enum.map_join(failure.errors, ", ", & &1.message))

    conn
    |> put_flash(:error, "Signing in didn't work. Please try again.")
    |> redirect(to: after_failure(conn))
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    case Accounts.find_or_create_from_google(auth) do
      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Signing in didn't work. Please try again.")
        |> redirect(to: after_failure(conn))

      found ->
        complete_sign_in(conn, found, get_session(conn, "return_to"))
    end
  end

  def dev_login(conn, params) do
    if dev_login_enabled?() do
      found = params["name"] |> dev_name() |> Accounts.find_or_create_dev()
      complete_sign_in(conn, found, params["return_to"])
    else
      conn
      |> put_flash(:error, "Dev login is off.")
      |> redirect(to: ~p"/signin")
    end
  end

  def logout(conn, _params) do
    disconnect_live_views(conn)

    conn
    |> clear_session()
    |> put_session("guest_id", Guest.new_id())
    |> configure_session(renew: true)
    |> put_flash(:info, "You're logged out.")
    |> redirect(to: ~p"/")
  end

  @spec sign_in_available?() :: boolean()
  def sign_in_available?, do: google_configured?() or dev_login_enabled?()

  @spec dev_login_enabled?() :: boolean()
  def dev_login_enabled?, do: Application.get_env(:three_sixes, :dev_login_enabled, false)

  @spec google_configured?() :: boolean()
  def google_configured? do
    :ueberauth
    |> Application.get_env(Ueberauth.Strategy.Google.OAuth, [])
    |> Keyword.get(:client_id)
    |> is_binary()
  end

  defp dev_name(name) when is_binary(name) do
    case String.trim(name) do
      "" -> "Dana"
      name -> name
    end
  end

  defp dev_name(_name), do: "Dana"

  defp store_return_to(conn, _opts) do
    case local_path(conn.params["return_to"]) do
      nil -> delete_session(conn, "return_to")
      path -> put_session(conn, "return_to", path)
    end
  end

  defp complete_sign_in(conn, {found, account}, return_to) do
    guest_id = get_session(conn, "guest_id")
    if guest_id, do: Accounts.take_over_guest(Accounts.guest_person_id(guest_id), account)

    disconnect_live_views(conn)

    conn
    |> put_session("account_id", account.id)
    |> put_session("live_socket_id", "account_session:" <> Guest.new_id())
    |> put_session("was_guest_id", guest_id)
    |> put_session("new_account", if(found == :created, do: true))
    |> delete_session("return_to")
    |> configure_session(renew: true)
    |> redirect(to: local_path(return_to) || ~p"/")
  end

  defp disconnect_live_views(conn) do
    if live_socket_id = get_session(conn, "live_socket_id") do
      ThreeSixesWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end
  end

  defp after_failure(conn) do
    case local_path(get_session(conn, "return_to")) do
      nil -> ~p"/signin"
      "/r/" <> code = room when code != "" -> room
      path -> ~p"/signin?#{[return_to: path]}"
    end
  end

  defp local_path("//" <> _), do: nil

  defp local_path("/" <> _ = path) do
    if String.contains?(path, ["\\", "/%09" | @control_characters]), do: nil, else: path
  end

  defp local_path(_), do: nil
end
