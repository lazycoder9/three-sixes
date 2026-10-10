defmodule ThreeSixesWeb.Guest do
  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    conn
    |> put_new_session("guest_id", &new_id/0)
    |> put_new_session("live_socket_id", fn -> "guest_session:" <> new_id() end)
  end

  @spec new_id() :: String.t()
  def new_id, do: 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  defp put_new_session(conn, key, value) do
    case get_session(conn, key) do
      nil -> put_session(conn, key, value.())
      _value -> conn
    end
  end
end
