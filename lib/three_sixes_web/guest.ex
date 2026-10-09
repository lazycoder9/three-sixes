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

  @spec new_id() :: String.t()
  def new_id, do: 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
