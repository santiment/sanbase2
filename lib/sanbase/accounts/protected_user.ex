defmodule Sanbase.Accounts.ProtectedUser do
  @moduledoc """
  Source of truth for the set of `are_activity_traces_hidden = true`
  user ids used by the privacy-masking pipeline. Cached per-node in
  `:persistent_term` with a 30-minute TTL and refreshed lazily on read —
  no GenServer / Task — so every hot-path consumer (Cache.hash,
  RequestContext.from_conn, the Logger filter, the Sentry scrubber) pays
  the recompute cost at most once per TTL per BEAM node.

  Flip the flag through `Sanbase.Accounts.User.hide_activity_traces!/1` /
  `unhide_activity_traces!/1`. Those call `refresh/0`, which recomputes
  on the current node AND fans out to every connected libcluster peer
  (typically the admin → web pods path) so the change applies cluster-
  wide immediately rather than waiting up to 30 minutes for the TTL.
  """

  alias Sanbase.Repo
  alias Sanbase.Accounts.User

  import Ecto.Query

  @key __MODULE__
  @ttl_seconds 30 * 60

  @spec cache_key() :: atom()
  def cache_key(), do: @key

  @spec activity_traces_hidden_user_ids() :: MapSet.t(non_neg_integer())
  def activity_traces_hidden_user_ids() do
    now = System.monotonic_time(:second)

    case :persistent_term.get(@key, nil) do
      {%MapSet{} = ids, added_at} when now - added_at <= @ttl_seconds -> ids
      _ -> refresh_local()
    end
  end

  @spec activity_traces_hidden?(non_neg_integer() | nil) :: boolean()
  def activity_traces_hidden?(user_id) when is_integer(user_id) do
    MapSet.member?(activity_traces_hidden_user_ids(), user_id)
  end

  def activity_traces_hidden?(_), do: false

  @doc """
  Refreshes the cache on this node and every connected libcluster peer.
  Called from `User.hide_activity_traces!/1` and `unhide_activity_traces!/1`
  so an admin-side toggle reaches the web pods without waiting for TTL.

  Fan-out is fire-and-forget `Node.spawn/2` — same pattern used elsewhere
  in the codebase (e.g. `Sanbase.Metric.Registry`). A peer that's down or
  unreachable simply misses this refresh and will recompute on its own
  next TTL boundary.
  """
  @spec refresh() :: MapSet.t(non_neg_integer())
  def refresh() do
    ids = refresh_local()

    Node.list()
    |> Enum.each(fn node -> Node.spawn(node, __MODULE__, :refresh_local, []) end)

    ids
  end

  @doc """
  Recomputes the cache on the local node only. Public so peers reached
  via `Node.spawn/2` can invoke it; do not call directly for cluster-wide
  refresh — use `refresh/0`.
  """
  @spec refresh_local() :: MapSet.t(non_neg_integer())
  def refresh_local() do
    ids =
      from(u in User, where: u.are_activity_traces_hidden == true, select: u.id)
      |> Repo.all()
      |> MapSet.new()

    :persistent_term.put(@key, {ids, System.monotonic_time(:second)})
    ids
  end

  @doc """
  Back-dates the cached entry past the TTL so the next read recomputes
  from the DB. Used by tests; also handy for ops to force a refresh on
  one node without restarting.
  """
  @spec expire_cache!() :: :ok
  def expire_cache!() do
    case :persistent_term.get(@key, nil) do
      {%MapSet{} = ids, _added_at} ->
        :persistent_term.put(@key, {ids, System.monotonic_time(:second) - @ttl_seconds - 60})

      _ ->
        :ok
    end

    :ok
  end
end
