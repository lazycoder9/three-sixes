defmodule ThreeSixesWeb.PageController do
  use ThreeSixesWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
