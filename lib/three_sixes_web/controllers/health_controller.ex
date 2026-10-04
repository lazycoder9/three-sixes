defmodule ThreeSixesWeb.HealthController do
  use ThreeSixesWeb, :controller

  def show(conn, _params), do: text(conn, "OK")
end
