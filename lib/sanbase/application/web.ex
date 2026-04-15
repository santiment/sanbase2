defmodule Sanbase.Application.Web do
  import Sanbase.ApplicationUtils

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

      # Rehydrating cache — intentionally NOT started in the test env.
      #
      # `Sanbase.Cache.RehydratingCache` is a globally-named GenServer that
      # periodically re-runs every registered closure. In test, closures
      # registered inside a `with_mocks` block can outlive that block and
      # fire later against real code paths (e.g. Clickhouse adapters),
      # producing intermittent
      #   "could not lookup Ecto repo Sanbase.ClickhouseRepo"
      # warnings during otherwise unrelated tests and making the suite
      # flaky. Gating the supervisor here keeps the test app clean by
      # default; tests that genuinely need RC (e.g.
      # `project_available_metrics_test.exs` and the dedicated
      # `rehydrating_cache_test.exs`) start a per-test supervisor via
      # `start_supervised!`, which ExUnit tears down at test exit.
      start_in(Sanbase.Cache.RehydratingCache.Supervisor, [:dev, :prod]),

      # Oban instance responsible for sending emails
      {Oban, oban_web_config()},

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
