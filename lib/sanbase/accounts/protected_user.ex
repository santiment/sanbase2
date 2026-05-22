defmodule Sanbase.Accounts.ProtectedUser do
  @moduledoc """
  Source of truth for the set of `are_activity_traces_hidden = true` user ids used
  by the privacy-masking pipeline. Cached in `:persistent_term` with a
  30-minute TTL and refreshed lazily on read — no GenServer / Task — so
  every hot-path consumer (Cache.hash, RequestContext.from_conn, the
  Logger filter, the Sentry scrubber) pays the recompute cost at most
  once per TTL per BEAM node.

  Flip the flag through `Sanbase.Accounts.User.hide_activity_traces!/1` /
  `unhide_activity_traces!/1` to roll the change out on the current node
  immediately; `refresh/0` is the same primitive exposed for ops scripts.
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
      _ -> compute_and_store()
    end
  end

  @spec activity_traces_hidden?(non_neg_integer() | nil) :: boolean()
  def activity_traces_hidden?(user_id) when is_integer(user_id) do
    MapSet.member?(activity_traces_hidden_user_ids(), user_id)
  end

  def activity_traces_hidden?(_), do: false

  @spec refresh() :: MapSet.t(non_neg_integer())
  def refresh(), do: compute_and_store()

  defp compute_and_store() do
    ids =
      from(u in User, where: u.are_activity_traces_hidden == true, select: u.id)
      |> Repo.all()
      |> MapSet.new()

    :persistent_term.put(@key, {ids, System.monotonic_time(:second)})
    ids
  end
end
