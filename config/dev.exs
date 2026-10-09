import Config

config :three_sixes, ThreeSixes.Repo,
  database: Path.expand("../three_sixes_dev.db", __DIR__),
  pool_size: 5,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true

config :three_sixes, ThreeSixesWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT") || "4000")],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "KUNACAq1gInemwMONxV7tye5pIUspMwg+DBY8gIWvKoxjEvgV6MSjQfJk5jZDcPl",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:three_sixes, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:three_sixes, ~w(--watch)]}
  ]

config :three_sixes, ThreeSixesWeb.Endpoint,
  live_reload: [
    web_console_logger: true,
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/three_sixes_web/(?:controllers|live|components|router)/?.*\.(ex|heex)$"
    ]
  ]

config :three_sixes, dev_routes: true, dev_login_enabled: true

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  # Changing either annotation flag takes `mix clean` and a full recompile.
  debug_heex_annotations: true,
  debug_attributes: true,
  enable_expensive_runtime_checks: true
