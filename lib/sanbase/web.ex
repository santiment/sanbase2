defmodule Sanbase.Application.Web do
  import Sanbase.ApplicationUtils
  require Logger

  def init() do
    # Change kafka consumer configuration at runtime before consumer supervisor is started
    Sanbase.Kafka.init()

    # API metrics
    SanbaseWeb.Graphql.Prometheus.HistogramInstrumenter.install(SanbaseWeb.Graphql.Schema)
    SanbaseWeb.Graphql.Prometheus.CounterInstrumenter.install(SanbaseWeb.Graphql.Schema)
  end

  @doc ~s"""
  Return the children and options that will be started in the web container.
  Along with these children all children from `Sanbase.Application.common_children/0`
  will be started, too.
  """
  def children() do
    # Define workers and child supervisors to be supervised
    children = [
      {Absinthe.Subscription, SanbaseWeb.Endpoint},

      # Start the graphQL in-memory cache
      Supervisor.child_spec(
        {ConCache,
         [
           name: :graphql_cache,
           ttl_check_interval: :timer.seconds(30),
           global_ttl: :timer.minutes(5),
           acquire_lock_timeout: 30_000
         ]},
        id: :api_cache
      ),

      # Time sereies Twitter DB connection
      Sanbase.Twitter.Store.child_spec(),

      # Rehydrating cache
      Sanbase.Cache.RehydratingCache.Supervisor,
      # Transform a list of transactions into a list of transactions
      # where addresses are marked whether or not they are an exchange address
      Sanbase.Clickhouse.MarkExchanges,

      # Start Kafka consumer supervisor
      start_in(
        %{
          id: Kaffe.GroupMemberSupervisor,
          start: {Kaffe.GroupMemberSupervisor, :start_link, []},
          type: :supervisor
        },
        [:prod]
      ),

      # Start libcluster
      start_in(
        {Cluster.Supervisor,
         [
           Application.get_env(:libcluster, :topologies),
           [name: Sanbase.ClusterSupervisor]
         ]},
        [:prod]
      )
    ]

    opts = [strategy: :one_for_one, name: Sanbase.WebSupervisor, max_restarts: 5, max_seconds: 1]

    {children, opts}
  end
end
