defmodule Sanbase.Cluster.PostgresStrategy do
  @moduledoc """
  A thin wrapper around `LibclusterPostgres.Strategy` (libcluster_postgres 0.2.0)
  that starts the LISTEN connection with `auto_reconnect: true`.

  The library starts `Postgrex.Notifications` without `:auto_reconnect` (and drops
  it from the config), so when Postgres closes the connection (e.g. during a
  maintenance window) the notifications process stops with
  `DBConnection.ConnectionError` and takes the linked strategy GenServer down with
  it. With `auto_reconnect: true` the notifications process stays alive, reconnects
  with backoff and re-issues the LISTEN once connected again.

  All callbacks are delegated to the library, so the heartbeat protocol (channel
  name and `NOTIFY "<channel>", '<node>'` payload) is exactly the same and nodes
  running the original strategy and this one still discover each other.

  The options are also passed to `Postgrex.start_link/1` for the heartbeat
  connection, which is a DBConnection pool that ignores them (it reconnects on its
  own).
  """
  use GenServer

  alias LibclusterPostgres.Strategy

  # Time between reconnect attempts of the LISTEN connection while Postgres is down
  @reconnect_backoff 2_000

  def start_link(args), do: GenServer.start_link(__MODULE__, args)

  @impl true
  def init(args) do
    {:ok, state, continue} = Strategy.init(args)

    opts =
      state.meta.opts.()
      |> Keyword.merge(auto_reconnect: true, reconnect_backoff: @reconnect_backoff)

    {:ok, put_in(state.meta.opts, fn -> opts end), continue}
  end

  @impl true
  def handle_continue(msg, state), do: Strategy.handle_continue(msg, state)

  @impl true
  def handle_info(msg, state), do: Strategy.handle_info(msg, state)
end
