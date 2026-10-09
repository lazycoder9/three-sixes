import Config

if System.get_env("PHX_SERVER") do
  config :three_sixes, ThreeSixesWeb.Endpoint, server: true
end

# Kamal passes unset secrets as empty strings.
present = fn name ->
  case String.trim(System.get_env(name, "")) do
    "" -> nil
    value -> value
  end
end

google_client_id = present.("GOOGLE_CLIENT_ID")
google_client_secret = present.("GOOGLE_CLIENT_SECRET")

if google_client_id && google_client_secret do
  config :ueberauth, Ueberauth.Strategy.Google.OAuth,
    client_id: google_client_id,
    client_secret: google_client_secret
end

if dev_login_enabled = present.("DEV_LOGIN_ENABLED") do
  config :three_sixes,
    dev_login_enabled: String.downcase(dev_login_enabled) in ["1", "true", "on", "yes"]
end

if config_env() == :prod do
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: /etc/three_sixes/three_sixes.db
      """

  config :three_sixes, ThreeSixes.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :three_sixes, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :three_sixes, ThreeSixesWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base
end
