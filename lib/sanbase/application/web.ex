defmodule Sanbase.Application.Web do
  import Sanbase.ApplicationUtils
  require Logger

  def init() do
    :ok
  end

  @doc ~s"""
  Return the children and options that will be started in the web container.
  Along with these children all children from `Sanbase.Application.common_children/0`
  will be started, too.
  """
  def children() do
    # Define workers and child supervisors to be supervised
    children = [
      # Start GraphQL subscriptions
      {Absinthe.Subscription, SanbaseWeb.Endpoint},

      # Sweeping the Guardian JWT refresh tokens
      {Guardian.DB.Sweeper, [interval: 20 * 60 * 1000]},

      # Rehydrating cache
      Sanbase.Cache.RehydratingCache.Supervisor,

      # Oban instance responsible for sending emails
      {Oban, oban_web_config()},

      # MCP server registry
      Hermes.Server.Registry,

      # MCP server for metrics access
      {SanbaseWeb.MCP.MetricsServer, transport: :streamable_http},

      # Start libcluster
      start_in(
        {Cluster.Supervisor,
         [
           Application.get_env(:libcluster, :topologies),
           [name: Sanbase.ClusterSupervisor]
         ]},
        [:dev, :prod]
      )
    ]

    opts = [
      name: Sanbase.WebSupervisor,
      strategy: :one_for_one,
      max_restarts: 5,
      max_seconds: 1
    ]

    {children, opts}
  end

  defp oban_web_config() do
    config = Application.fetch_env!(:sanbase, Oban.Web)

    # In case the DB config or URL is pointing to production, put the proper
    # schema in the config. This will be used both on prod and locally when
    # connecting to the stage DB. This is automated so when the stage DB is
    # used, the config should not be changed manually to include the schema
    case Sanbase.Utils.prod_db?() do
      true -> Keyword.put(config, :prefix, "sanbase2")
      false -> config
    end
  end
end
