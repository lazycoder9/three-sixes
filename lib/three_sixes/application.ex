defmodule ThreeSixes.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ThreeSixesWeb.Telemetry,
      ThreeSixes.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:three_sixes, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:three_sixes, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ThreeSixes.PubSub},
      ThreeSixesWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: ThreeSixes.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    ThreeSixesWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations? do
    System.get_env("RELEASE_NAME") == nil
  end
end
