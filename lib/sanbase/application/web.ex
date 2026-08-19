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
      # `Sanbase.Cache.RehydratingCache` is a globally-named GenServer periodically
      # re-running every registered closure. In test a closure registered inside a
      # `with_mocks` block can outlive it and fire against real code paths (Clickhouse
      # adapters), giving intermittent "could not lookup Ecto repo Sanbase.ClickhouseRepo"
      # warnings in unrelated tests. Tests that genuinely need RC
      # (`project_available_metrics_test.exs`, `rehydrating_cache_test.exs`) start a
      # per-test supervisor via `start_supervised!`.
      start_in(Sanbase.Cache.RehydratingCache.Supervisor, [:dev, :prod]),

      # Oban instance responsible for sending emails.
      # Wrapped in a dedicated supervisor with a relaxed restart policy so
      # transient `Oban.Sonar` crashes during dev recompiles don't cascade.
      start_if(
        fn -> {Sanbase.Application.ObanSupervisor, config: oban_web_config()} end,
        &Sanbase.Application.ObanSupervisor.enabled?/0
      ),

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

    # When the DB config or URL points to production, put the proper schema in the config.
    # Used on prod and locally against the stage DB, automated so nobody has to add the
    # schema by hand.
    case Sanbase.Utils.prod_db?() do
      true -> Keyword.put(config, :prefix, "sanbase2")
      false -> config
    end
  end
end
