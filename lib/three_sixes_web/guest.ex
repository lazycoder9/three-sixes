defmodule ThreeSixesWeb.Guest do
  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case get_session(conn, "guest_id") do
      nil -> put_session(conn, "guest_id", new_id())
      _guest_id -> conn
    end
  end

  @spec on_mount(:default, map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()}
  def on_mount(:default, _params, %{"guest_id" => guest_id}, socket) do
    {:cont, Phoenix.Component.assign(socket, :person_id, "guest:" <> guest_id)}
  end

  defp new_id, do: 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
