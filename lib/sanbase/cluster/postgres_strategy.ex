defmodule Sanbase.Cluster.PostgresStrategy do
  @moduledoc """
  Wraps `LibclusterPostgres.Strategy` so its LISTEN connection uses `auto_reconnect: true`
  and a closed Postgres connection no longer crashes the strategy. All callbacks are
  delegated, so the heartbeat protocol is unchanged. Relies on the 0.2.0 internal `meta.opts`.
  """
  use GenServer

  alias LibclusterPostgres.Strategy

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
