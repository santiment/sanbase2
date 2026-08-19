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

  This process owns the socket, the subscription lifecycle and the export
  path. Everything else lives in sibling modules it drives:

    * `Sanbase.Hyperliquid.Bbo.Quarantine` — which coins must not be
      subscribed and why: crash forensics, probation, pipelined probes,
      convictions, audit verdicts, the env ignore list, and the send log
      used as crash evidence.
    * `Sanbase.Hyperliquid.Bbo.CoinUniverse` — the audit itself: fetching
      HL's tradeable universe and flagging unsubscribable coins with reasons.
    * `Sanbase.Hyperliquid.Bbo.Reconnect` — the backoff ladder, jitter,
      connect-rate tracking and disconnect-cause wording.
    * `Sanbase.Hyperliquid.Bbo.BboPoint` — frame payload parsing and the
      Kafka key/value encoding.

  ## Lifecycle

  1. **Boot.** `start_link/0` opens the WebSocket. On `handle_connect/2` all
     periodic timers are armed, an immediate `:reconcile_subscriptions` is
     sent to populate subs, and a universe audit is kicked off (rate-limited
     to one per `@audit_min_gap_ms`, so a crash-looping scraper never hammers
     the HL info endpoint; also refreshed every `@audit_interval`).

  2. **Reconcile (every 60s).** Loads the mappings, diffs the desired coin
     set against `active_subs`, and queues `subscribe`/`unsubscribe` frames.
     Coins excluded by Quarantine are skipped and unsubscribed if active;
     coins on probation are left to the probe worker; new bulk subscribes
     are deferred while probes are in flight (verdicts must stay
     unambiguous) and queued in random order (so a fixed-point-in-drain kill
     can't implicate the same innocent coins every time). A coin whose
     subscribe went out a full round ago without a `subscriptionResponse`
     moves to probation instead of being re-sent forever.

  3. **Outbound pacing.** Sub/unsub frames drain from the queue one per
     `@flush_subs_interval` (200ms) — Hyperliquid caps outbound at 2000/min.
     Every sent subscribe is recorded in Quarantine's send log.

  4. **Inbound BBO.** A `bbo` frame is parsed (`BboPoint.parse_frame_data/4`),
     fanned out to every slug mapped to that coin, and pushed via
     `KafkaExporter.persist_async/2`. Per coin: the first frame in a
     `coalesce_window_ms` window emits immediately; later frames in the same
     window overwrite a `coalesce_buffer` slot (latest wins). A
     `:flush_coalesced` tick (every 250ms) emits buffered entries whose
     window has elapsed.

  5. **Liveness.** Outbound `ping` every 30s (HL closes idle sockets ~60s).
     A `:healthcheck` tick every 60s counts misses when no frame arrived for
     `@healthcheck_tolerance`; too many consecutive misses raise
     `HealthcheckError` so the supervisor restarts the process.

  6. **Disconnect.** `handle_disconnect/2` first runs crash forensics
     (`Quarantine.handle_crash/3`), then clears the connection state and
     sleeps the `Reconnect` backoff (plus jitter) before reconnecting into
     step 1.

  7. **Probes (`:probe_next`, every 400ms).** `Quarantine.probe_tick/5`
     re-tries probation coins on a settled connection — pipelined, paced by
     Quarantine's spacing — and tells this process which subscribe frame to
     queue.
  """

  use WebSockex

  require Logger

  alias Sanbase.Hyperliquid.Bbo.BboPoint
  alias Sanbase.Hyperliquid.Bbo.CoinUniverse
  alias Sanbase.Hyperliquid.Bbo.Quarantine
  alias Sanbase.Hyperliquid.Bbo.Reconnect
  alias Sanbase.Project.SourceSlugMapping
  alias Sanbase.Utils.Config

  @name :hyperliquid_bbo_scraper
  @exporter :hyperliquid_bbo_exporter
  @url "wss://api.hyperliquid.xyz/ws"
  @source "hyperliquid"

  # HL closes idle sockets after ~60s.
  @ping_interval 30_000
  @healthcheck_interval 60_000
  # Max gap between inbound frames before counting a miss.
  @healthcheck_tolerance 60_000
  # Misses tolerated before raising and forcing a reconnect.
  @healthcheck_max_failures 5
  # Resync subscriptions against SourceSlugMapping.
  @reconcile_interval 60_000
  @audit_interval 300_000
  # Floor between audit runs, whatever triggers them, so a crash loop cannot hammer HL.
  @audit_min_gap_ms 30_000
  # HL allows 2000 outbound messages/min; 1 per 200ms = 300/min leaves ~85% headroom.
  @flush_subs_interval 200
  @flush_coalesced_interval 250
  # Per-coin debounce; overridable via app config.
  @coalesce_window_default_ms 1_000
  # Probe starts land on this grid, so it must divide the 1600ms probe spacing evenly.
  @probe_interval 400

  def child_spec(_opts \\ []) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, []}}
  end

  def start_link() do
    state = initial_state()

    # A new pid means a supervisor restart (fresh state, quarantine forgotten); reconnects
    # keep it. Logged on every connect/disconnect/terminate line to tell the two apart.
    case WebSockex.start_link(@url, __MODULE__, state, name: @name) do
      {:ok, pid} = ok ->
        Logger.info("[HyperliquidBboWS] started pid=#{inspect(pid)} url=#{@url}")
        ok

      {:error, reason} = error ->
        Logger.warning("[HyperliquidBboWS] failed to start: #{inspect(reason)}")
        error
    end
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
      # Coin discipline, kept across reconnects. See Sanbase.Hyperliquid.Bbo.Quarantine.
      quarantine: Quarantine.new(),
      # Coins awaiting a subscribe confirmation at the end of the previous reconcile round;
      # only coins present in BOTH rounds get probated. Cleared on disconnect.
      prev_unconfirmed: MapSet.new(),
      slug_map: %{},
      pending_sub_queue: :queue.new(),
      last_emitted: %{},
      coalesce_buffer: %{},
      reconnect_backoff_ms: Reconnect.initial_backoff_ms(),
      last_message_time: System.system_time(:millisecond),
      healthcheck_failures: 0,
      coalesce_window_ms: coalesce_window_ms(),
      timers: %{},
      # Diagnostics. connected_at/bbo_in reset per connection, reconnects is cumulative.
      # Read via Map.get/bump so a hot recompile against an old state never raises.
      connected_at: nil,
      bbo_in: 0,
      reconnects: 0,
      # Connect timestamps (ms) of the last minute, newest first. HL allows 30/min/IP.
      connect_times: [],
      last_audit_at: 0,
      # Ref of the newest in-flight audit; only its result is applied.
      audit_ref: nil,
      # Diagnostics: %{coin => %{point: map, exported_at_ms: ms, count: n}} of the last
      # point handed to Kafka. Never cleared, so :sys.get_state/1 still answers "ever
      # exported, when, how often" after a reconnect.
      last_exported: %{}
    }
  end

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
    connect_times = Reconnect.track_connect(Map.get(state, :connect_times, []), now)

    Logger.info(
      "[HyperliquidBboWS] connected pid=#{inspect(self())} " <>
        "reconnects=#{Map.get(state, :reconnects, 0)} " <>
        "backoff_was=#{state.reconnect_backoff_ms}ms connects_last_60s=#{length(connect_times)} " <>
        "(HL allows 30 new conns/min per IP, all clients behind the IP combined)"
    )

    state =
      %{state | last_message_time: now}
      # Map.merge is recompile-safe. The backoff is NOT reset here - only a connection
      # surviving the stability threshold earns that (see Reconnect), else a remote
      # dropping us seconds after connect pins the backoff at its minimum.
      |> Map.merge(%{
        connected_at: System.monotonic_time(:millisecond),
        bbo_in: 0,
        connect_times: connect_times,
        quarantine: Quarantine.on_connect(quarantine_state(state))
      })
      |> schedule_all_timers()
      |> maybe_start_audit()

    send(self(), :reconcile_subscriptions)
    {:ok, state}
  end

  def handle_disconnect(status, state) do
    connected_at = Map.get(state, :connected_at)

    lifetime_ms =
      if connected_at, do: System.monotonic_time(:millisecond) - connected_at, else: nil

    # WebSockex always passes a status map here; crash loudly if that contract changes.
    reason = Map.get(status, :reason)
    attempt = Map.get(status, :attempt_number, 1)

    {base_ms, next_backoff_ms} = Reconnect.plan(state.reconnect_backoff_ms, lifetime_ms, attempt)
    sleep_ms = base_ms + Reconnect.jitter_ms(base_ms)

    now = System.system_time(:millisecond)
    q = quarantine_state(state)

    # lifetime_ms tells a fixed cadence (policy/limit) from a random drop (network);
    # bbo_in>0 means data flowed until the drop; pending_subs>0 means we died mid-drain;
    # last_subs_sent names the trigger when the same coin keeps preceding the crash.
    mono_now = System.monotonic_time(:millisecond)

    Logger.warning(
      "[HyperliquidBboWS] disconnect pid=#{inspect(self())} " <>
        "cause=#{Reconnect.describe_cause(reason)} attempt=#{attempt} " <>
        "lifetime_ms=#{inspect(lifetime_ms)} " <>
        "last_frame_age_ms=#{now - state.last_message_time} " <>
        "bbo_in=#{Map.get(state, :bbo_in, 0)} active_subs=#{MapSet.size(state.active_subs)} " <>
        "pending_subs=#{:queue.len(state.pending_sub_queue)} " <>
        "last_subs_sent=[#{Quarantine.recent_sends_summary(q, mono_now)}] " <>
        "probation=#{length(Quarantine.probation(q))} " <>
        "quarantined=#{map_size(q.quarantined)} " <>
        "reconnects=#{Map.get(state, :reconnects, 0)} backoff=#{sleep_ms}ms"
    )

    state =
      state
      |> handle_crash_suspects(mono_now, attempt)
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

  # A pid that never reappears after this = the supervisor started a replacement
  # process with fresh state (quarantine/probation forgotten).
  def terminate(reason, _state) do
    Logger.warning(
      "[HyperliquidBboWS] terminate pid=#{inspect(self())} reason=#{inspect(reason)}"
    )

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

  # Export path

  defp handle_bbo(%{"coin" => coin, "time" => time_ms, "bbo" => [bid, ask]}, state) do
    with slugs when is_list(slugs) <- Map.get(state.slug_map, coin),
         point_data when not is_nil(point_data) <-
           BboPoint.parse_frame_data(coin, time_ms, bid, ask) do
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

  defp emit(slugs, data) do
    tuples =
      Enum.map(slugs, fn slug ->
        struct(BboPoint, Map.put(data, :slug, slug))
        |> BboPoint.json_kv_tuple()
      end)

    :ok = Sanbase.KafkaExporter.persist_async(tuples, @exporter)
  end

  # Map.update with a default (not `%{state | ...}`) so a process predating the key lives.
  defp record_exported(state, coin, data) do
    entry = %{
      point: data,
      exported_at_ms: System.system_time(:millisecond),
      count: get_in(state, [:last_exported, coin, :count]) |> Kernel.||(0) |> Kernel.+(1)
    }

    Map.update(state, :last_exported, %{coin => entry}, &Map.put(&1, coin, entry))
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

  # Verdicts and probe selection live in Quarantine; this supplies the connection facts
  # and queues the subscribe frame when a probe starts.
  def handle_info(:probe_next, state) do
    {q, action} =
      Quarantine.probe_tick(
        quarantine_state(state),
        state.active_subs,
        connection_uptime_ms(state),
        :queue.is_empty(state.pending_sub_queue),
        System.monotonic_time(:millisecond)
      )

    state = Map.put(state, :quarantine, q)

    state =
      case action do
        {:subscribe, coin} ->
          state
          |> Map.update!(:pending_sub_queue, &:queue.in({"subscribe", coin}, &1))
          |> maybe_schedule_flush_subs()

        :noop ->
          state
      end

    {:ok, schedule(state, :probe_next, @probe_interval)}
  end

  def handle_info(:reconcile_subscriptions, state) do
    state =
      state
      |> reconcile()
      |> schedule(:reconcile_subscriptions, @reconcile_interval)

    {:ok, state}
  end

  # One frame per tick, re-armed only while frames remain. The just-fired timer ref is
  # stale - clear it first so maybe_schedule_flush_subs/1 sees an accurate state. Sent
  # subscribes go to Quarantine as crash evidence, with slugs resolved now.
  def handle_info(:flush_subs, state) do
    state = %{state | timers: Map.delete(state.timers, :flush_subs)}

    case :queue.out(state.pending_sub_queue) do
      {{:value, {method, coin}}, queue2} ->
        state = %{state | pending_sub_queue: queue2}

        if send_banned?(state, method, coin) do
          Logger.info(
            "[HyperliquidBboWS] dropping queued subscribe coin=#{coin} — " <>
              "excluded or probated after it was queued"
          )

          {:ok, maybe_schedule_flush_subs(state)}
        else
          state =
            state
            |> track_sub_send(method, coin)
            |> maybe_schedule_flush_subs()

          {:reply, sub_frame(method, coin), state}
        end

      {:empty, _} ->
        {:ok, state}
    end
  end

  def handle_info(:flush_coalesced, state) do
    now = System.system_time(:millisecond)
    window = state.coalesce_window_ms

    # Reconcile prunes the buffer only for coins in active_subs, so a coin buffered before
    # its sub was confirmed can outlive its slug_map entry. Drop it, don't crash below.
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

  def handle_info(:audit, state) do
    {:ok, state |> maybe_start_audit() |> schedule(:audit, @audit_interval)}
  end

  # Only the NEWEST in-flight audit counts: the ref must match the one stored at spawn,
  # else a slow older audit replies last and overwrites fresh verdicts. Any change to the
  # exclusion *set* reconciles at once instead of waiting out the 60s tick; already-queued
  # subscribes are then dropped at send time by send_banned?/3.
  def handle_info({:audit_result, ref, %{reasons: reasons}}, state) do
    if ref == Map.get(state, :audit_ref) do
      prev_keys = quarantine_state(state).audit_excluded |> Map.keys() |> MapSet.new()
      next_keys = reasons |> Map.keys() |> MapSet.new()
      if prev_keys != next_keys, do: send(self(), :reconcile_subscriptions)

      {:ok, Map.put(state, :quarantine, Quarantine.apply_audit(quarantine_state(state), reasons))}
    else
      Logger.info("[HyperliquidBboWS] ignoring stale audit result (a newer audit was started)")
      {:ok, state}
    end
  end

  # Failed audit (error tuple) — keep the previous verdicts.
  def handle_info({:audit_result, _ref, _}, state), do: {:ok, state}

  def handle_info(_msg, state), do: {:ok, state}

  # Reconcile

  defp reconcile(state) do
    {full_desired, slug_map} = load_mappings()
    q = quarantine_state(state)
    excluded = Quarantine.excluded(q)
    probation = Quarantine.probation(q)

    # Everything mapped, minus excluded coins and coins on probation (those are retried by
    # the probe worker, never by the bulk subscribe).
    desired_set =
      full_desired
      |> MapSet.difference(MapSet.new(Map.keys(excluded)))
      |> MapSet.difference(MapSet.new(probation))

    # In-flight probes subscribed their coins on purpose - don't unsubscribe mid-verdict.
    probe_exempt = MapSet.new(Quarantine.probing_coins(q))

    to_subscribe = MapSet.difference(desired_set, state.active_subs)
    {state, to_subscribe} = probate_unconfirmed(state, to_subscribe)
    to_subscribe = defer_while_probing(to_subscribe, q)

    to_unsubscribe =
      state.active_subs
      |> MapSet.difference(desired_set)
      |> MapSet.difference(probe_exempt)

    if MapSet.size(to_subscribe) > 0 or MapSet.size(to_unsubscribe) > 0 do
      Logger.info(
        "[HyperliquidBboWS] reconcile +sub=#{MapSet.size(to_subscribe)} -unsub=#{MapSet.size(to_unsubscribe)} desired=#{MapSet.size(desired_set)} excluded=#{map_size(excluded)} probation=#{length(probation)}"
      )
    end

    # Tuples, not encoded frames - flush_subs needs the coin to record what was sent.
    # Shuffled because MapSet order is deterministic: if the remote kills the connection at
    # a fixed point in the drain (e.g. an IP limit), the same innocent coins sit
    # newest-before-death every time. Random order makes a repeat offender a real signal.
    new_queue =
      to_subscribe
      |> Enum.shuffle()
      |> Enum.reduce(state.pending_sub_queue, fn coin, queue ->
        :queue.in({"subscribe", coin}, queue)
      end)

    new_queue =
      Enum.reduce(to_unsubscribe, new_queue, fn coin, queue ->
        :queue.in({"unsubscribe", coin}, queue)
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
  end

  # While probes are in flight, defer NEW bulk subscribes to the next reconcile (<=60s) so
  # probe frames are the only unconfirmed subscribes on the wire and their verdict is
  # unambiguous. Unsubscribes proceed - they don't trigger kills.
  defp defer_while_probing(to_subscribe, q) do
    case Quarantine.probing_coins(q) do
      [] ->
        to_subscribe

      probing_coins ->
        if MapSet.size(to_subscribe) > 0 do
          Logger.info(
            "[HyperliquidBboWS] deferring #{MapSet.size(to_subscribe)} subscribe(s) " <>
              "until the probes of #{inspect(probing_coins)} resolve"
          )
        end

        MapSet.new()
    end
  end

  # A subscribe sent a full reconcile round ago with no subscriptionResponse means HL
  # silently ignored it - the audit only checks pair names, this proves a coin streams.
  # Such coins go to probation for a probe verdict instead of being re-queued forever.
  # Requires two reconcile rounds of uptime and an empty queue, so churn stays silent.
  defp probate_unconfirmed(state, to_subscribe) do
    age_ms = connection_uptime_ms(state)

    stuck =
      if age_ms > 2 * @reconcile_interval and :queue.is_empty(state.pending_sub_queue),
        do: MapSet.intersection(to_subscribe, Map.get(state, :prev_unconfirmed, MapSet.new())),
        else: MapSet.new()

    if MapSet.size(stuck) == 0 do
      {state, to_subscribe}
    else
      q =
        Quarantine.probate(
          quarantine_state(state),
          stuck |> MapSet.to_list() |> Enum.sort(),
          "subscribe sent, no subscriptionResponse after #{div(age_ms, 1000)}s connected"
        )

      {Map.put(state, :quarantine, q), MapSet.difference(to_subscribe, stuck)}
    end
  end

  defp load_mappings() do
    # HL lists crypto projects and non-crypto assets (gold, SPX), so take either kind.
    # `:all` excludes hidden assets: hiding one stops its export within a reconcile.
    rows = SourceSlugMapping.get_source_slug_mappings(@source, return: :all)

    slug_map =
      Enum.reduce(rows, %{}, fn {coin, slug}, acc ->
        Map.update(acc, coin, [slug], &[slug | &1])
      end)

    {MapSet.new(Map.keys(slug_map)), slug_map}
  end

  defp sub_frame(method, coin) do
    {:text, Jason.encode!(%{method: method, subscription: %{type: "bbo", coin: coin}})}
  end

  # A subscribe queued before a verdict landed must not reach the wire - the queue lags
  # reconcile by (queue length x @flush_subs_interval). Unsubscribes always pass, and so do
  # probe subscribes: their coin is on probation by design, marked in-flight before queuing.
  defp send_banned?(state, "subscribe", coin) do
    q = quarantine_state(state)

    Map.has_key?(Quarantine.excluded(q), coin) or
      (coin in Quarantine.probation(q) and coin not in Quarantine.probing_coins(q))
  end

  defp send_banned?(_state, _method, _coin), do: false

  # Quarantine glue

  # Crash forensics, run BEFORE active_subs is cleared. attempt > 1 is a failed reconnect:
  # no new frames were sent, nothing to learn.
  defp handle_crash_suspects(state, _now, attempt) when attempt != 1, do: state

  defp handle_crash_suspects(state, now, 1) do
    q = Quarantine.handle_crash(quarantine_state(state), state.active_subs, now)
    Map.put(state, :quarantine, q)
  end

  defp track_sub_send(state, "subscribe", coin) do
    q =
      Quarantine.track_send(
        quarantine_state(state),
        coin,
        Map.get(state.slug_map, coin, []),
        System.monotonic_time(:millisecond)
      )

    Map.put(state, :quarantine, q)
  end

  defp track_sub_send(state, _method, _coin), do: state

  # Recompile-safe: a process predating the :quarantine key gets a fresh struct.
  defp quarantine_state(state), do: Map.get(state, :quarantine) || Quarantine.new()

  defp connection_uptime_ms(state) do
    case Map.get(state, :connected_at) do
      nil -> 0
      at -> System.monotonic_time(:millisecond) - at
    end
  end

  # Audit in a supervised task so its HTTP calls never block frame handling, at most once
  # per @audit_min_gap_ms whatever triggers it - last_audit_at survives disconnects, so a
  # crash-connect loop stays rate-limited. The timestamp advances at SPAWN, not at result
  # receipt: the gap bounds requests against HL, and the next :audit tick retries a crash.
  defp maybe_start_audit(state) do
    now = System.system_time(:millisecond)

    if now - Map.get(state, :last_audit_at, 0) >= @audit_min_gap_ms do
      parent = self()
      # The gap bounds audit STARTS, not durations, so audits can overlap and a stale
      # reply must not overwrite a newer verdict (see the :audit_result handler).
      ref = make_ref()

      Task.Supervisor.start_child(Sanbase.TaskSupervisor, fn ->
        send(parent, {:audit_result, ref, CoinUniverse.audit()})
      end)

      state
      |> Map.put(:last_audit_at, now)
      |> Map.put(:audit_ref, ref)
    else
      state
    end
  end

  # Timers

  defp schedule_all_timers(state) do
    state
    |> schedule(:ping, @ping_interval)
    |> schedule(:healthcheck, @healthcheck_interval)
    |> schedule(:flush_coalesced, @flush_coalesced_interval)
    |> schedule(:reconcile_subscriptions, @reconcile_interval)
    |> schedule(:probe_next, @probe_interval)
    |> schedule(:audit, @audit_interval)
  end

  # Arm only with something to drain and no timer pending, else we poll an empty queue.
  defp maybe_schedule_flush_subs(state) do
    cond do
      :queue.is_empty(state.pending_sub_queue) -> state
      Map.has_key?(state.timers, :flush_subs) -> state
      true -> schedule(state, :flush_subs, @flush_subs_interval)
    end
  end

  # Creates the key at 1 if the running process predates it (hot recompile via `r/1`).
  defp bump(state, key), do: Map.update(state, key, 1, &(&1 + 1))

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
