defmodule ThreeSixesWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint ThreeSixesWeb.Endpoint

      use ThreeSixesWeb, :verified_routes

      import Plug.Conn
      import Phoenix.ConnTest
      import ThreeSixesWeb.ConnCase
    end
  end

  setup tags do
    ThreeSixes.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
