import Config

config :three_sixes,
  ecto_repos: [ThreeSixes.Repo],
  generators: [timestamp_type: :utc_datetime]

config :three_sixes, ThreeSixes.Repo, journal_mode: :wal

config :three_sixes, :dice, ThreeSixes.Dice.Crypto

config :three_sixes, ThreeSixesWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ThreeSixesWeb.ErrorHTML, json: ThreeSixesWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ThreeSixes.PubSub,
  live_view: [signing_salt: "G9dTbFWX"]

config :esbuild,
  version: "0.25.4",
  three_sixes: [
    args:
      ~w(js/app.ts --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

config :tailwind,
  version: "4.1.7",
  three_sixes: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

# Last, so the environment's config overrides everything above.
import_config "#{config_env()}.exs"
