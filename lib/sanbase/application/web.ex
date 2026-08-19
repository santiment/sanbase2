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

      # Deliberately NOT started in test: this globally-named GenServer periodically re-runs
      # every registered closure, and one registered inside a `with_mocks` block can outlive
      # it and fire against real code, giving intermittent "could not lookup Ecto repo
      # Sanbase.ClickhouseRepo" warnings in unrelated tests. Tests that need it start a
      # per-test supervisor via `start_supervised!`.
      start_in(Sanbase.Cache.RehydratingCache.Supervisor, [:dev, :prod]),

      # The email-sending Oban instance, wrapped in its own supervisor with a relaxed
      # restart policy so transient `Oban.Sonar` crashes during dev recompiles do not
      # cascade.
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

    # A DB config or URL pointing to production gets the proper schema put in the config,
    # so nobody has to add it by hand on prod or locally against the stage DB.
    case Sanbase.Utils.prod_db?() do
      true -> Keyword.put(config, :prefix, "sanbase2")
      false -> config
    end
  end
end
