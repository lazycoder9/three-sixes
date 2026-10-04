defmodule ThreeSixesWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :three_sixes

  @session_options [
    store: :cookie,
    key: "_three_sixes_key",
    signing_salt: "nDRQ7uTx",
    same_site: "Lax",
    max_age: 365 * 24 * 60 * 60
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [:peer_data, :x_headers, session: @session_options]],
    longpoll: [connect_info: [:peer_data, :x_headers, session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :three_sixes,
    gzip: not code_reloading?,
    only: ThreeSixesWeb.static_paths()

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :three_sixes
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug ThreeSixesWeb.Router
end
