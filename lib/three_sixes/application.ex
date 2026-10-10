defmodule ThreeSixes.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    max_rooms = Application.get_env(:three_sixes, :max_rooms, 5_000)

    children = [
      ThreeSixesWeb.Telemetry,
      ThreeSixes.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:three_sixes, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:three_sixes, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: ThreeSixes.PubSub},
      {Registry, keys: :unique, name: ThreeSixes.Rooms.Registry},
      {DynamicSupervisor,
       name: ThreeSixes.Rooms.Supervisor, max_children: max_rooms, max_restarts: max_rooms},
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
