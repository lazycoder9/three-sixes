import Config

config :three_sixes, ThreeSixes.Repo,
  database: Path.expand("../three_sixes_test#{System.get_env("MIX_TEST_PARTITION")}.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

config :three_sixes, :dice, ThreeSixes.Dice.Scripted

config :three_sixes, :max_rooms, 500

config :three_sixes, ThreeSixesWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "pUTNIFvSlKSaBh+eDNB2D+NIr3WYZ1ckf7iQyxhbMS6Q6CTDXlS/ycyPVSa6U+lN",
  server: false

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  enable_expensive_runtime_checks: true
