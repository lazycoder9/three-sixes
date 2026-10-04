# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :three_sixes,
  ecto_repos: [ThreeSixes.Repo],
  generators: [timestamp_type: :utc_datetime]

config :three_sixes, ThreeSixes.Repo, journal_mode: :wal

config :three_sixes, :dice, ThreeSixes.Dice.Crypto

# Configures the endpoint
config :three_sixes, ThreeSixesWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ThreeSixesWeb.ErrorHTML, json: ThreeSixesWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ThreeSixes.PubSub,
  live_view: [signing_salt: "G9dTbFWX"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  three_sixes: [
    args:
      ~w(js/app.ts --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  three_sixes: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
