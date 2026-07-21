defmodule SanbaseWeb.Graphql.CacheMonitor do
  @moduledoc """
  Periodically logs GraphQL cache statistics and enforces a byte-size bound.

  Every tick it logs:

      GraphQL cache stats: entries=152340 table_memory_mb=27.4 payload_mb=214.8

  and when the payload exceeds `:max_payload_mb`, it triggers an LRW sweep
  (`Cachex.prune/3`) that removes the oldest entries until the payload is
  back under the bound (with a margin), logging a warning with the
  before/after numbers.

  This complements `SanbaseWeb.Graphql.CachexBoundEnforcer`, which bounds the
  **entry count** synchronously on every write: a count bound alone cannot
  express a memory bound when entry sizes vary. Computing the payload size
  requires an O(n) table walk (~40ms per 200k entries; the gzipped values are
  refc binaries invisible to `:ets.info(:memory)`), which is why this check
  is periodic rather than per-write.

  ## How much is swept per clean

  The sweep is proportional to the overshoot, not a fixed count:

      removed = entries - trunc(entries × max_bytes/payload_bytes × 0.9)

  i.e. the removed fraction is `1 - 0.9 × bound/payload`:

    * payload just over the bound  -> ~10% of entries (the 0.9 margin)
    * payload 1.1× over            -> ~18%
    * payload 2× over              -> ~55%

  Since the check runs every tick, the first trigger normally happens "just
  over" the bound, so a typical sweep removes 10-20% of entries, oldest
  first (LRW — entries are written once, so `:modified` order is insertion
  order). `Cachex.prune/3` purges expired entries first and credits them
  against the eviction quota, so live evictions are often fewer.

  Two deliberate properties:

    * The proportional target assumes roughly uniform entry sizes. When a
      few huge entries dominate the payload a single sweep may under- or
      over-shoot; the next tick corrects.
    * The sweep is uncapped on purpose: it restores the bound within one
      tick. A capped, gentler sweep would let the payload stay above the
      bound for several minutes during a spike — the wrong trade-off for an
      OOM guard.
  """

  use GenServer

  require Logger

  alias SanbaseWeb.Graphql.CachexProvider

  @default_interval :timer.minutes(1)
  @default_max_payload_mb 1024
  # Sweep below the bound by this margin so sweeps don't re-trigger every tick
  @sweep_margin 0.9

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl GenServer
  def init(opts) do
    state = %{
      cache: Keyword.get(opts, :cache, :graphql_cache),
      interval: Keyword.get(opts, :interval, @default_interval),
      max_payload_bytes: Keyword.get(opts, :max_payload_mb, @default_max_payload_mb) * 1024 * 1024
    }

    schedule(state.interval)
    {:ok, state}
  end

  @impl GenServer
  def handle_info(:check, state) do
    check(state)
    schedule(state.interval)
    {:noreply, state}
  end

  defp check(state) do
    case :ets.info(state.cache, :size) do
      :undefined ->
        :ok

      entries ->
        payload_bytes = CachexProvider.payload_bytes(state.cache)

        Logger.info(
          "GraphQL cache stats: entries=#{entries} " <>
            "table_memory_mb=#{CachexProvider.size(state.cache)} " <>
            "payload_mb=#{mb(payload_bytes)}"
        )

        if payload_bytes > state.max_payload_bytes do
          sweep(state, entries, payload_bytes)
        end
    end

    :ok
  end

  defp sweep(state, entries, payload_bytes) do
    keep_ratio = state.max_payload_bytes / payload_bytes * @sweep_margin
    target_entries = trunc(entries * keep_ratio)

    {:ok, true} = Cachex.prune(state.cache, target_entries, reclaim: 0.0)

    Logger.warning(
      "GraphQL cache payload #{mb(payload_bytes)} MB exceeded the " <>
        "#{mb(state.max_payload_bytes)} MB bound — swept the oldest entries: " <>
        "entries #{entries} -> #{CachexProvider.count(state.cache)}, " <>
        "payload #{mb(payload_bytes)} MB -> #{mb(CachexProvider.payload_bytes(state.cache))} MB"
    )
  end

  defp mb(bytes), do: Float.round(bytes / (1024 * 1024), 2)

  defp schedule(interval) do
    Process.send_after(self(), :check, interval)
  end
end
