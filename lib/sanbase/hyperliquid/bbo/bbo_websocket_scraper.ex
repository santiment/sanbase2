defmodule Sanbase.Hyperliquid.Bbo.WebsocketScraper do
  defmodule HealthcheckError do
    defexception [:message]
  end

  @moduledoc ~s"""
  Realtime best-bid/offer exporter for Hyperliquid perpetual futures.

  Subscribes per-coin to the `bbo` channel on `wss://api.hyperliquid.xyz/ws`.
  Coins are derived from `Sanbase.Project.SourceSlugMapping` rows with
  `source = "hyperliquid"`. Each `bbo` frame is coalesced to at most one Kafka
  emit per coin per `coalesce_window_ms` (trailing-edge debounce) and pushed to
  the `:hyperliquid_bbo_exporter` Kafka exporter.

  ## Lifecycle

  1. **Boot.** `start_link/0` opens the WebSocket. On `handle_connect/2` all
     periodic timers are armed and an immediate `:reconcile_subscriptions` is
     sent to populate subs.

  2. **Reconcile (every 60s).** Loads `SourceSlugMapping` rows for
     `hyperliquid`, builds a `coin -> [slug, ...]` map, and diffs against
     `active_subs`. New coins get a `subscribe` frame queued; removed coins
     get `unsubscribe` plus their `coalesce_buffer`/`last_emitted` entries pruned.

  3. **Outbound pacing.** Sub/unsub frames are drained from the queue one per
     `@flush_subs_interval` (50ms) — Hyperliquid caps outbound at 2000/min.
     The drain timer self-disarms when the queue empties and re-arms when
     reconcile queues more frames.

  4. **Inbound BBO.** A `bbo` frame is parsed into a `BboPoint`, fanned out
     to every slug mapped to that coin, and pushed via
     `KafkaExporter.persist_async/2`. Per coin: the first frame in a
     `coalesce_window_ms` window emits immediately; later frames in the same
     window overwrite a `coalesce_buffer` slot (latest wins).

  5. **Coalesce flush (every 250ms).** Walks `coalesce_buffer` and emits any entry
     whose window has elapsed. Bounds the worst-case extra latency at the
     window boundary to one tick (~250ms).

  6. **Liveness.** Outbound `ping` every 50s. A `:healthcheck` tick every 60s
     checks `now - last_message_time`; if it exceeds
     `@healthcheck_tolerance`, a miss is counted. After
     `@healthcheck_max_failures` consecutive misses the process raises
     `HealthcheckError` and the supervisor restarts it.

  7. **Disconnect.** `handle_disconnect/2` cancels timers, clears
     `active_subs`/`pending_sub_queue`/`coalesce_buffer`/`last_emitted`/
     `healthcheck_failures`, then sleeps a backoff (plus jitter) before
     reconnecting. The backoff doubles per disconnect (total sleep, jitter
     included, capped at `@reconnect_max_ms`) and resets to
     `@reconnect_initial_ms` only after a
     connection survives `@stable_connection_ms` — a connection that dies
     young keeps backing off, so a remote that kills us seconds after connect
     (e.g. per-IP rate limiting) slows us down instead of locking us into a
     reconnect storm that keeps the IP over the limit. Reconnect re-enters
     step 1.
  """

  use WebSockex

  require Logger

  alias Sanbase.Hyperliquid.Bbo.BboPoint
  alias Sanbase.Hyperliquid.Bbo.CoinUniverse
  alias Sanbase.Project.SourceSlugMapping
  alias Sanbase.Utils.Config

  @name :hyperliquid_bbo_scraper
  @exporter :hyperliquid_bbo_exporter
  @url "wss://api.hyperliquid.xyz/ws"
  @source "hyperliquid"

  # Outbound app-level ping; HL closes idle sockets ~60s.
  @ping_interval 30_000
  # Periodic check that we've received a frame recently.
  @healthcheck_interval 60_000
  # Max gap between inbound frames before counting a miss.
  @healthcheck_tolerance 60_000
  # Consecutive misses tolerated before raising and forcing reconnect.
  @healthcheck_max_failures 5
  # Resync subscriptions against SourceSlugMapping on this cadence.
  @reconcile_interval 60_000
  # Throttle for the (best-effort, non-blocking) coin-universe audit run from
  # reconcile, so a reconnect storm can't hammer the HL `info` endpoint.
  @audit_interval 300_000

  # Hyperliquid limits outbound client messages to 2000/min (~33/sec). We pace
  # subscribe/unsubscribe frames at 1 per 50ms = 20/sec = 1200/min — ~40%
  # headroom. Cold-start burst of ~200 coins drains in ~10s, well under.
  @flush_subs_interval 50

  # Tick rate for draining the per-coin coalesce buffer.
  @flush_coalesced_interval 250
  # Default debounce window per coin; overridable via app config.
  @coalesce_window_default_ms 1_000
  # First reconnect delay; doubles per consecutive disconnect, capped below.
  @reconnect_initial_ms 1_000
  # Hard ceiling on a single reconnect sleep, jitter included.
  @reconnect_max_ms 20_000
  # A connection must live this long before the next disconnect starts the
  # backoff over from @reconnect_initial_ms; anything shorter keeps doubling.
  @stable_connection_ms 60_000
  # Cap on the random jitter added to each reconnect sleep, so instances
  # sharing an egress IP don't reconnect in lockstep (HL limits are per IP,
  # aggregated across every client behind it).
  @reconnect_jitter_max_ms 1_000
  # The exponential part of the backoff caps here so base + jitter never
  # exceeds @reconnect_max_ms.
  @reconnect_base_cap_ms @reconnect_max_ms - @reconnect_jitter_max_ms
  # Rolling window for counting our own connects, matching the window of HL's
  # "30 new connections per minute per IP" limit.
  @connects_window_ms 60_000

  def child_spec(_opts \\ []) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, []}}
  end

  def start_link() do
    state = initial_state()
    Logger.info("[HyperliquidBboWS] starting url=#{@url}")
    WebSockex.start_link(@url, __MODULE__, state, name: @name)
  end

  def enabled?() do
    Config.module_get(__MODULE__, :enabled?)
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> Kernel.in(["true", "1"])
  end

  defp initial_state() do
    %{
      active_subs: MapSet.new(),
      # Coins Hyperliquid does not know about (per the periodic universe audit).
      # Excluded from subscriptions in reconcile/2 and kept across reconnects so
      # a storm never re-subscribes to known-bad coins. Refreshed each audit, so
      # a coin re-listed on HL is picked back up automatically.
      unsupported: MapSet.new(),
      # Coins that were already awaiting a subscribe confirmation at the end
      # of the previous reconcile round. warn_unconfirmed/2 only flags coins
      # present in BOTH rounds, so a coin queued for the first time this
      # round is never reported as "never confirmed". Cleared on disconnect.
      prev_unconfirmed: MapSet.new(),
      slug_map: %{},
      pending_sub_queue: :queue.new(),
      last_emitted: %{},
      coalesce_buffer: %{},
      reconnect_backoff_ms: @reconnect_initial_ms,
      last_message_time: System.system_time(:millisecond),
      healthcheck_failures: 0,
      coalesce_window_ms: coalesce_window_ms(),
      timers: %{},
      # Diagnostics. connected_at/bbo_in are reset per connection in
      # handle_connect/2; reconnects is cumulative since boot. Read via
      # Map.get/bump so a hot recompile against an old state never raises.
      connected_at: nil,
      bbo_in: 0,
      reconnects: 0,
      # Timestamps (ms) of successful connects in the last minute, newest
      # first — compared against HL's 30 new connections/min/IP limit.
      connect_times: [],
      last_audit_at: 0,
      # Diagnostics: per-coin record of the last point actually handed to the
      # Kafka exporter — %{coin => %{point: map, exported_at_ms: ms, count: n}}.
      # Never cleared (not on disconnect, not on unsubscribe) so it answers
      # "has this coin ever exported, when, and how many times" via
      # :sys.get_state/1 even after reconnects. Bounded by the mapped-coin set.
      last_exported: %{}
    }
  end

  # Record a successful emit for diagnostics. Map.update with a default (not
  # `%{state | ...}`) so a live process predating this key never raises.
  defp record_exported(state, coin, data) do
    entry = %{
      point: data,
      exported_at_ms: System.system_time(:millisecond),
      count: get_in(state, [:last_exported, coin, :count]) |> Kernel.||(0) |> Kernel.+(1)
    }

    Map.update(state, :last_exported, %{coin => entry}, &Map.put(&1, coin, entry))
  end

  # Safe counter bump — creates the key at 1 if the running process predates it
  # (relevant when recompiling this module against a live process via `r/1`).
  defp bump(state, key), do: Map.update(state, key, 1, &(&1 + 1))

  defp coalesce_window_ms() do
    case Config.module_get(__MODULE__, :coalesce_window_ms) do
      ms when is_integer(ms) -> ms
      ms when is_binary(ms) -> ms |> String.trim() |> String.to_integer()
      _ -> @coalesce_window_default_ms
    end
  end

  # WebSockex callbacks

  def handle_connect(_conn, state) do
    now = System.system_time(:millisecond)

    connect_times =
      [now | Map.get(state, :connect_times, [])]
      |> Enum.take_while(&(now - &1 < @connects_window_ms))

    Logger.info(
      "[HyperliquidBboWS] connected reconnects=#{Map.get(state, :reconnects, 0)} " <>
        "backoff_was=#{state.reconnect_backoff_ms}ms connects_last_60s=#{length(connect_times)} " <>
        "(HL allows 30 new conns/min per IP, all clients behind the IP combined)"
    )

    state =
      %{state | last_message_time: now}
      # Reset per-connection diagnostics; Map.merge is recompile-safe. The
      # reconnect backoff is deliberately NOT reset here — only a connection
      # that survives @stable_connection_ms earns a reset (handle_disconnect),
      # otherwise a remote that drops us seconds after connect pins the
      # backoff at its minimum forever. connected_at is monotonic because the
      # backoff-reset decision depends on it — an NTP step of the wall clock
      # must not fake a "stable" lifetime.
      |> Map.merge(%{
        connected_at: System.monotonic_time(:millisecond),
        bbo_in: 0,
        connect_times: connect_times
      })
      |> schedule_all_timers()

    send(self(), :reconcile_subscriptions)
    {:ok, state}
  end

  def handle_disconnect(status, state) do
    connected_at = Map.get(state, :connected_at)

    lifetime_ms =
      if connected_at, do: System.monotonic_time(:millisecond) - connected_at, else: nil

    # WebSockex always passes a connection-status map here; crash loudly if
    # that contract ever changes rather than guessing at the shape.
    reason = Map.get(status, :reason)
    attempt = Map.get(status, :attempt_number, 1)

    {base_ms, next_backoff_ms} = backoff_plan(state.reconnect_backoff_ms, lifetime_ms, attempt)
    # Jitter de-syncs instances sharing an egress IP; proportional to the
    # backoff so a healthy single reconnect stays fast, and bounded so
    # base + jitter never exceeds @reconnect_max_ms.
    sleep_ms = base_ms + :rand.uniform(min(base_ms, @reconnect_jitter_max_ms))

    # lifetime_ms shows whether the socket dies on a fixed cadence
    # (policy/limit) or randomly (network); bbo_in>0 means data was flowing
    # right up to the drop (so mappings are fine); pending_subs>0 means we
    # died mid-drain of the subscribe queue.
    Logger.warning(
      "[HyperliquidBboWS] disconnect cause=#{disconnect_cause(reason)} attempt=#{attempt} " <>
        "lifetime_ms=#{inspect(lifetime_ms)} " <>
        "last_frame_age_ms=#{System.system_time(:millisecond) - state.last_message_time} " <>
        "bbo_in=#{Map.get(state, :bbo_in, 0)} active_subs=#{MapSet.size(state.active_subs)} " <>
        "pending_subs=#{:queue.len(state.pending_sub_queue)} " <>
        "reconnects=#{Map.get(state, :reconnects, 0)} backoff=#{sleep_ms}ms"
    )

    state =
      state
      |> cancel_timers()
      |> Map.merge(%{
        active_subs: MapSet.new(),
        pending_sub_queue: :queue.new(),
        coalesce_buffer: %{},
        last_emitted: %{},
        healthcheck_failures: 0,
        connected_at: nil,
        prev_unconfirmed: MapSet.new(),
        reconnect_backoff_ms: next_backoff_ms
      })
      |> bump(:reconnects)

    Process.sleep(sleep_ms)
    {:reconnect, state}
  end

  @doc false
  # The reconnect schedule after a disconnect: `{sleep_base_ms, next_backoff_ms}`.
  # `sleep_base_ms` is slept now (plus jitter); `next_backoff_ms` is stored for
  # the disconnect after this one, so the ladder walks
  # @reconnect_initial_ms, 2x, 4x, ... up to @reconnect_base_cap_ms. Only a
  # dropped live connection (attempt == 1) that survived @stable_connection_ms
  # restarts the ladder; short-lived connections and failed reconnect attempts
  # (attempt > 1, where lifetime_ms is nil) keep climbing. Public only for
  # tests — handle_disconnect/2 can't be exercised without a real 1s+ sleep.
  def backoff_plan(current_backoff_ms, lifetime_ms, attempt) do
    stable? = attempt == 1 and is_integer(lifetime_ms) and lifetime_ms >= @stable_connection_ms

    base_ms =
      if stable?,
        do: @reconnect_initial_ms,
        else: min(current_backoff_ms, @reconnect_base_cap_ms)

    {base_ms, min(base_ms * 2, @reconnect_base_cap_ms)}
  end

  # The remote's stated reason for the drop, in words. `{:remote, :closed}` is
  # an abrupt TCP close with NO WebSocket close frame — the remote never said
  # why; no more detail exists on the wire. HL/CloudFront drop connections
  # this way when per-IP limits are exceeded (10 concurrent conns, 30 new
  # conns/min, 2000 client msgs/min, 1000 subs — aggregated over every client
  # behind the IP), so persistent short lifetimes + this cause usually mean
  # IP-level rate limiting rather than an app error. A graceful close frame
  # (code + message) surfaces via the clause below.
  defp disconnect_cause({:remote, :closed}),
    do: "remote dropped TCP without a close frame (no reason on wire; rate-limit/infra style)"

  defp disconnect_cause({:remote, code, msg}),
    do: "remote sent close frame code=#{inspect(code)} msg=#{inspect(msg)}"

  defp disconnect_cause({:local, reason}), do: "closed by our side: #{inspect(reason)}"
  defp disconnect_cause(other), do: inspect(other)

  def terminate(reason, _state) do
    Logger.warning("[HyperliquidBboWS] terminate reason=#{inspect(reason)}")
    :ok
  end

  def handle_frame({:text, json}, state) when is_binary(json) do
    state = %{state | last_message_time: System.system_time(:millisecond)}

    case Jason.decode(json) do
      {:ok, decoded} ->
        handle_decoded(decoded, state)

      {:error, _} ->
        Logger.warning("[HyperliquidBboWS] Bad JSON: #{json}")
        {:ok, state}
    end
  end

  def handle_frame(_frame, state), do: {:ok, state}

  defp handle_decoded(%{"channel" => "pong"}, state), do: {:ok, state}

  defp handle_decoded(%{"channel" => "subscriptionResponse", "data" => sr}, state) do
    {:ok, handle_sub_response(sr, state)}
  end

  defp handle_decoded(%{"channel" => "bbo", "data" => data}, state) do
    {:ok, handle_bbo(data, bump(state, :bbo_in))}
  end

  defp handle_decoded(%{"channel" => "error"} = msg, state) do
    Logger.warning("[HyperliquidBboWS] Error frame: #{inspect(msg)}")
    {:ok, state}
  end

  defp handle_decoded(_msg, state), do: {:ok, state}

  defp handle_sub_response(
         %{"method" => "subscribe", "subscription" => %{"type" => "bbo", "coin" => coin}},
         state
       ) do
    %{state | active_subs: MapSet.put(state.active_subs, coin)}
  end

  defp handle_sub_response(
         %{"method" => "unsubscribe", "subscription" => %{"type" => "bbo", "coin" => coin}},
         state
       ) do
    %{state | active_subs: MapSet.delete(state.active_subs, coin)}
  end

  defp handle_sub_response(_other, state), do: state

  defp handle_bbo(%{"coin" => coin, "time" => time_ms, "bbo" => [bid, ask]}, state) do
    with slugs when is_list(slugs) <- Map.get(state.slug_map, coin),
         point_data when not is_nil(point_data) <- build_point_data(coin, time_ms, bid, ask) do
      now = System.system_time(:millisecond)
      last = Map.get(state.last_emitted, coin)

      if is_nil(last) or now - last >= state.coalesce_window_ms do
        emit(slugs, point_data)

        %{
          state
          | last_emitted: Map.put(state.last_emitted, coin, now),
            coalesce_buffer: Map.delete(state.coalesce_buffer, coin)
        }
        |> record_exported(coin, point_data)
      else
        %{state | coalesce_buffer: Map.put(state.coalesce_buffer, coin, point_data)}
      end
    else
      _ -> state
    end
  end

  defp handle_bbo(_, state), do: state

  defp build_point_data(coin, time_ms, bid, ask) do
    {bp, bv} = parse_side(bid)
    {ap, av} = parse_side(ask)

    if Enum.all?([bp, bv, ap, av], &is_nil/1) do
      nil
    else
      %{
        coin: coin,
        timestamp_ms: time_ms,
        bid_price: bp,
        bid_volume: bv,
        ask_price: ap,
        ask_volume: av
      }
    end
  end

  defp parse_side(nil), do: {nil, nil}

  defp parse_side(%{"px" => px, "sz" => sz}) do
    {parse_float(px), parse_float(sz)}
  end

  defp parse_side(_), do: {nil, nil}

  defp parse_float(nil), do: nil
  defp parse_float(n) when is_number(n), do: n * 1.0

  defp parse_float(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp emit(slugs, data) do
    tuples =
      Enum.map(slugs, fn slug ->
        struct(BboPoint, Map.put(data, :slug, slug))
        |> BboPoint.json_kv_tuple()
      end)

    :ok = Sanbase.KafkaExporter.persist_async(tuples, @exporter)
  end

  # handle_info

  def handle_info(:ping, state) do
    state = schedule(state, :ping, @ping_interval)
    frame = {:text, Jason.encode!(%{method: "ping"})}
    {:reply, frame, state}
  end

  def handle_info(:healthcheck, state) do
    now = System.system_time(:millisecond)
    elapsed = now - state.last_message_time

    state =
      if elapsed > @healthcheck_tolerance do
        Logger.warning(
          "[HyperliquidBboWS] healthcheck miss elapsed=#{elapsed}ms failures=#{state.healthcheck_failures + 1}"
        )

        Map.update!(state, :healthcheck_failures, &(&1 + 1))
      else
        %{state | healthcheck_failures: 0}
      end

    if state.healthcheck_failures > @healthcheck_max_failures do
      raise HealthcheckError,
        message: "More than #{@healthcheck_max_failures} consecutive healthchecks have failed"
    end

    state = schedule(state, :healthcheck, @healthcheck_interval)
    {:ok, state}
  end

  def handle_info(:reconcile_subscriptions, state) do
    state =
      state
      |> reconcile()
      |> schedule(:reconcile_subscriptions, @reconcile_interval)

    {:ok, state}
  end

  # Drain one queued sub/unsub frame per tick, paced at @flush_subs_interval.
  # Re-arms only if more frames remain — when queue empties the timer stops
  # until reconcile kicks it again. The just-fired timer ref is stale; clear
  # it before deciding whether to re-arm so maybe_schedule_flush_subs/1 sees
  # an accurate timer state.
  def handle_info(:flush_subs, state) do
    state = %{state | timers: Map.delete(state.timers, :flush_subs)}

    case :queue.out(state.pending_sub_queue) do
      {{:value, frame}, queue2} ->
        state = %{state | pending_sub_queue: queue2} |> maybe_schedule_flush_subs()
        {:reply, frame, state}

      {:empty, _} ->
        {:ok, state}
    end
  end

  def handle_info(:flush_coalesced, state) do
    now = System.system_time(:millisecond)
    window = state.coalesce_window_ms

    # Reconcile prunes the buffer only for coins that were in active_subs, so a
    # coin buffered before its sub was confirmed can outlive its slug_map entry.
    # Drop such coins instead of crashing on the emit lookup below.
    buffer =
      Enum.filter(state.coalesce_buffer, fn {coin, _} ->
        Map.has_key?(state.slug_map, coin)
      end)

    {to_emit, still_buffered} =
      Enum.split_with(buffer, fn {coin, _} ->
        last = Map.get(state.last_emitted, coin)
        is_nil(last) or now - last >= window
      end)

    state =
      Enum.reduce(to_emit, state, fn {coin, data}, acc ->
        emit(Map.fetch!(acc.slug_map, coin), data)
        record_exported(acc, coin, data)
      end)

    new_last_emitted =
      Enum.reduce(to_emit, state.last_emitted, fn {coin, _}, acc -> Map.put(acc, coin, now) end)

    state =
      %{state | coalesce_buffer: Map.new(still_buffered), last_emitted: new_last_emitted}
      |> schedule(:flush_coalesced, @flush_coalesced_interval)

    {:ok, state}
  end

  # Refresh the `unsupported` set from an audit run; the next scheduled reconcile
  # (≤60s) applies it. A fetch failure returns a non-map result and is ignored,
  # keeping the previous set.
  def handle_info({:audit_result, %{unsupported: unsupported}}, state) do
    {:ok, Map.put(state, :unsupported, MapSet.new(unsupported))}
  end

  def handle_info({:audit_result, _}, state), do: {:ok, state}

  def handle_info(_msg, state), do: {:ok, state}

  # Reconcile

  defp reconcile(state) do
    {full_desired, slug_map} = load_mappings()
    unsupported = Map.get(state, :unsupported, MapSet.new())
    # Subscribe to everything we're mapped to, minus coins HL doesn't recognise.
    desired_set = MapSet.difference(full_desired, unsupported)

    to_subscribe = MapSet.difference(desired_set, state.active_subs)
    to_unsubscribe = MapSet.difference(state.active_subs, desired_set)

    warn_unconfirmed(state, to_subscribe)

    if MapSet.size(to_subscribe) > 0 or MapSet.size(to_unsubscribe) > 0 do
      Logger.info(
        "[HyperliquidBboWS] reconcile +sub=#{MapSet.size(to_subscribe)} -unsub=#{MapSet.size(to_unsubscribe)} desired=#{MapSet.size(desired_set)} excluded_unsupported=#{MapSet.size(unsupported)}"
      )
    end

    new_queue =
      Enum.reduce(to_subscribe, state.pending_sub_queue, fn coin, q ->
        :queue.in(sub_frame("subscribe", coin), q)
      end)

    new_queue =
      Enum.reduce(to_unsubscribe, new_queue, fn coin, q ->
        :queue.in(sub_frame("unsubscribe", coin), q)
      end)

    dropped = MapSet.to_list(to_unsubscribe)

    %{
      state
      | slug_map: slug_map,
        pending_sub_queue: new_queue,
        last_emitted: Map.drop(state.last_emitted, dropped),
        coalesce_buffer: Map.drop(state.coalesce_buffer, dropped)
    }
    |> Map.put(:prev_unconfirmed, to_subscribe)
    |> maybe_schedule_flush_subs()
    # Audit the FULL mapped set (not the reduced one) so a previously
    # unsupported coin that HL re-lists is detected and re-included.
    |> maybe_audit_coins(full_desired)
  end

  # Ground truth on coin support: a subscribe frame sent long ago that never
  # got a subscriptionResponse means HL silently ignored it. The universe
  # audit can overcount — spot *token* names pass it, but `bbo` only accepts
  # tradeable pair names (perps like "BTC"/"xyz:GOLD", spot pairs like
  # "@107") — so this is the check that proves a coin actually streams. Warns
  # only about coins already awaiting confirmation on the PREVIOUS reconcile
  # round (a coin appearing in to_subscribe for the first time hasn't even
  # had its subscribe frame queued yet — that happens after this check), and
  # only once the connection has outlived a couple of reconcile rounds with
  # an empty outbound queue; during connection churn it stays silent.
  defp warn_unconfirmed(state, to_subscribe) do
    still_unconfirmed =
      MapSet.intersection(to_subscribe, Map.get(state, :prev_unconfirmed, MapSet.new()))

    connected_at = Map.get(state, :connected_at)

    age_ms =
      if connected_at, do: System.monotonic_time(:millisecond) - connected_at, else: 0

    if age_ms > 2 * @reconcile_interval and MapSet.size(still_unconfirmed) > 0 and
         :queue.is_empty(state.pending_sub_queue) do
      coins = still_unconfirmed |> MapSet.to_list() |> Enum.sort()

      Logger.warning(
        "[HyperliquidBboWS] #{length(coins)} coin(s) never confirmed by HL " <>
          "after #{div(age_ms, 1000)}s connected (subscribe sent, no subscriptionResponse): " <>
          "#{inspect(coins)}"
      )
    end

    :ok
  end

  # Run the coin-universe audit off the WS process (so the HTTP call never
  # blocks frame handling) and no more than once per @audit_interval. The task
  # sends its result back to this process to refresh the `unsupported` set.
  defp maybe_audit_coins(state, desired_set) do
    now = System.system_time(:millisecond)

    if now - Map.get(state, :last_audit_at, 0) >= @audit_interval do
      parent = self()
      Task.start(fn -> send(parent, {:audit_result, CoinUniverse.audit(desired_set)}) end)
      Map.put(state, :last_audit_at, now)
    else
      state
    end
  end

  defp sub_frame(method, coin) do
    {:text, Jason.encode!(%{method: method, subscription: %{type: "bbo", coin: coin}})}
  end

  defp load_mappings() do
    # Hyperliquid lists both crypto projects and non-crypto assets (gold, SPX,
    # …), so subscribe to mappings of either kind. `:all` excludes hidden
    # assets by default: hiding one stops its Kafka export on the next
    # reconcile (≤60s), unhiding resumes it.
    rows = SourceSlugMapping.get_source_slug_mappings(@source, return: :all)

    slug_map =
      Enum.reduce(rows, %{}, fn {coin, slug}, acc ->
        Map.update(acc, coin, [slug], &[slug | &1])
      end)

    {MapSet.new(Map.keys(slug_map)), slug_map}
  end

  # Timers

  defp schedule_all_timers(state) do
    state
    |> schedule(:ping, @ping_interval)
    |> schedule(:healthcheck, @healthcheck_interval)
    |> schedule(:flush_coalesced, @flush_coalesced_interval)
    |> schedule(:reconcile_subscriptions, @reconcile_interval)
  end

  # Arms :flush_subs only when there's something to drain and no timer is
  # already pending. Avoids polling an empty queue forever.
  defp maybe_schedule_flush_subs(state) do
    cond do
      :queue.is_empty(state.pending_sub_queue) -> state
      Map.has_key?(state.timers, :flush_subs) -> state
      true -> schedule(state, :flush_subs, @flush_subs_interval)
    end
  end

  defp schedule(state, key, ms) do
    case Map.get(state.timers, key) do
      nil -> :ok
      ref -> Process.cancel_timer(ref)
    end

    ref = Process.send_after(self(), key, ms)
    %{state | timers: Map.put(state.timers, key, ref)}
  end

  defp cancel_timers(state) do
    Enum.each(state.timers, fn {_k, ref} -> Process.cancel_timer(ref) end)
    %{state | timers: %{}}
  end
end
