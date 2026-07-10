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

  1. **Boot.** `start_link/0` opens the WebSocket. On `handle_connect/2` the
     reconnect backoff is reset, all periodic timers are armed, and an
     immediate `:reconcile_subscriptions` is sent to populate subs.

  2. **Reconcile (every 60s).** Loads `SourceSlugMapping` rows for
     `hyperliquid`, builds a `coin -> [slug, ...]` map, and diffs against
     `active_subs`. New coins get a `subscribe` frame queued; removed coins
     get `unsubscribe` plus their `pending`/`last_emitted` entries pruned.

  3. **Outbound pacing.** Sub/unsub frames are drained from the queue one per
     `@flush_subs_interval` (50ms) — Hyperliquid caps outbound at 2000/min.
     The drain timer self-disarms when the queue empties and re-arms when
     reconcile queues more frames.

  4. **Inbound BBO.** A `bbo` frame is parsed into a `BboPoint`, fanned out
     to every slug mapped to that coin, and pushed via
     `KafkaExporter.persist_async/2`. Per coin: the first frame in a
     `coalesce_window_ms` window emits immediately; later frames in the same
     window overwrite a `pending` slot (latest wins).

  5. **Coalesce flush (every 250ms).** Walks `pending` and emits any entry
     whose window has elapsed. Bounds the worst-case extra latency at the
     window boundary to one tick (~250ms).

  6. **Liveness.** Outbound `ping` every 50s. A `:healthcheck` tick every 60s
     checks `now - last_message_time`; if it exceeds
     `@healthcheck_tolerance`, a miss is counted. After
     `@healthcheck_max_failures` consecutive misses the process raises
     `HealthcheckError` and the supervisor restarts it.

  7. **Disconnect.** `handle_disconnect/2` cancels timers, clears
     `active_subs`/`pending_sub_queue`/`pending`/`last_emitted`/
     `healthcheck_failures`, sleeps the current backoff, then doubles it
     (capped at `@reconnect_max_ms`). Reconnect re-enters step 1.
  """

  use WebSockex

  require Logger

  alias Sanbase.Hyperliquid.Bbo.BboPoint
  alias Sanbase.Project.SourceSlugMapping
  alias Sanbase.Utils.Config

  @name :hyperliquid_bbo_scraper
  @exporter :hyperliquid_bbo_exporter
  @url "wss://api.hyperliquid.xyz/ws"
  # REST endpoint that lists HL's full coin universe (perp `meta` + `spotMeta`).
  # Used to authoritatively tell whether a coin we subscribe to actually exists.
  @info_url "https://api.hyperliquid.xyz/info"
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
  # Upper bound on how long a synchronous single-coin verification (used when a
  # mapping is created) may block before we give up and let the insert through.
  @verify_timeout 5_000

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
  # Upper bound on the exponential reconnect backoff.
  @reconnect_max_ms 30_000

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
      slug_map: %{},
      pending_sub_queue: :queue.new(),
      last_emitted: %{},
      pending: %{},
      reconnect_backoff_ms: @reconnect_initial_ms,
      last_message_time: System.system_time(:millisecond),
      healthcheck_failures: 0,
      coalesce_window_ms: coalesce_window_ms(),
      timers: %{},
      # Diagnostics. Per-connection counters are reset in handle_connect/2;
      # reconnects is cumulative since boot. All read via Map.get/bump so a
      # hot recompile against an old state term never raises.
      connected_at: nil,
      msgs_out: 0,
      frames_in: 0,
      bbo_in: 0,
      errors_in: 0,
      reconnects: 0,
      last_audit_at: 0
    }
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

    Logger.info(
      "[HyperliquidBboWS] connected reconnects=#{Map.get(state, :reconnects, 0)} backoff_was=#{state.reconnect_backoff_ms}ms"
    )

    state =
      %{
        state
        | reconnect_backoff_ms: @reconnect_initial_ms,
          last_message_time: now
      }
      # Reset per-connection diagnostics; Map.merge is recompile-safe.
      |> Map.merge(%{connected_at: now, msgs_out: 0, frames_in: 0, bbo_in: 0, errors_in: 0})
      |> schedule_all_timers()

    send(self(), :reconcile_subscriptions)
    {:ok, state}
  end

  def handle_disconnect(status, state) do
    sleep_ms = state.reconnect_backoff_ms
    now = System.system_time(:millisecond)
    connected_at = Map.get(state, :connected_at)
    lifetime_ms = if connected_at, do: now - connected_at, else: nil

    # Full `status` (not just :reason) surfaces a WS close code/reason if the
    # remote sent a close frame. `{:remote, :closed}` = abrupt TCP close with
    # NO close frame — typical of an infra/rate-limit drop rather than an app
    # error. lifetime_ms tells us whether the socket dies on a fixed cadence
    # (policy/limit) or randomly (network). bbo_in>0 means subscriptions worked
    # and data was flowing right up to the drop (so mappings are fine).
    Logger.warning(
      "[HyperliquidBboWS] disconnect status=#{inspect(status)} lifetime_ms=#{inspect(lifetime_ms)} " <>
        "frames_in=#{Map.get(state, :frames_in, 0)} bbo_in=#{Map.get(state, :bbo_in, 0)} " <>
        "errors_in=#{Map.get(state, :errors_in, 0)} msgs_out=#{Map.get(state, :msgs_out, 0)} " <>
        "active_subs=#{MapSet.size(state.active_subs)} reconnects=#{Map.get(state, :reconnects, 0)} backoff=#{sleep_ms}ms"
    )

    state =
      state
      |> cancel_timers()
      |> Map.merge(%{
        active_subs: MapSet.new(),
        pending_sub_queue: :queue.new(),
        pending: %{},
        last_emitted: %{},
        healthcheck_failures: 0
      })
      |> Map.update!(:reconnect_backoff_ms, fn ms -> min(ms * 2, @reconnect_max_ms) end)
      |> bump(:reconnects)

    Process.sleep(sleep_ms)
    {:reconnect, state}
  end

  def terminate(reason, _state) do
    Logger.warning("[HyperliquidBboWS] terminate reason=#{inspect(reason)}")
    :ok
  end

  def handle_frame({:text, json}, state) when is_binary(json) do
    state = bump(%{state | last_message_time: System.system_time(:millisecond)}, :frames_in)

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
    {:ok, bump(state, :errors_in)}
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
            pending: Map.delete(state.pending, coin)
        }
      else
        %{state | pending: Map.put(state.pending, coin, point_data)}
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
    state = schedule(state, :ping, @ping_interval) |> bump(:msgs_out)
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
        state =
          %{state | pending_sub_queue: queue2} |> maybe_schedule_flush_subs() |> bump(:msgs_out)

        {:reply, frame, state}

      {:empty, _} ->
        {:ok, state}
    end
  end

  def handle_info(:flush_coalesced, state) do
    now = System.system_time(:millisecond)
    window = state.coalesce_window_ms

    {to_emit, still_pending} =
      Enum.split_with(state.pending, fn {coin, _} ->
        last = Map.get(state.last_emitted, coin)
        is_nil(last) or now - last >= window
      end)

    Enum.each(to_emit, fn {coin, data} ->
      emit(Map.fetch!(state.slug_map, coin), data)
    end)

    new_last_emitted =
      Enum.reduce(to_emit, state.last_emitted, fn {coin, _}, acc -> Map.put(acc, coin, now) end)

    state =
      %{state | pending: Map.new(still_pending), last_emitted: new_last_emitted}
      |> schedule(:flush_coalesced, @flush_coalesced_interval)

    {:ok, state}
  end

  # Refresh the `unsupported` set from an audit run. Only reconcile when the set
  # actually changed, so an unchanged audit doesn't churn subscriptions. A fetch
  # failure returns a non-map result and is ignored (keeps the previous set).
  def handle_info({:audit_result, %{unsupported: unsupported}}, state) do
    new_unsupported = MapSet.new(unsupported)
    old_unsupported = Map.get(state, :unsupported, MapSet.new())
    state = Map.put(state, :unsupported, new_unsupported)

    if MapSet.equal?(new_unsupported, old_unsupported) do
      {:ok, state}
    else
      Logger.info(
        "[HyperliquidBboWS] unsupported set updated size=#{MapSet.size(new_unsupported)}; reconciling"
      )

      send(self(), :reconcile_subscriptions)
      {:ok, state}
    end
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
        pending: Map.drop(state.pending, dropped)
    }
    |> maybe_schedule_flush_subs()
    # Audit the FULL mapped set (not the reduced one) so a previously
    # unsupported coin that HL re-lists is detected and re-included.
    |> maybe_audit_coins(full_desired)
  end

  # Run the coin-universe audit off the WS process (so the HTTP call never
  # blocks frame handling) and no more than once per @audit_interval. The task
  # sends its result back to this process to refresh the `unsupported` set.
  defp maybe_audit_coins(state, desired_set) do
    now = System.system_time(:millisecond)

    if now - Map.get(state, :last_audit_at, 0) >= @audit_interval do
      parent = self()
      Task.start(fn -> send(parent, {:audit_result, audit_coins(desired_set)}) end)
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

    {slug_map, nil_slug_coins} =
      Enum.reduce(rows, {%{}, []}, fn {coin, slug}, {acc, nils} ->
        nils = if is_nil(slug), do: [coin | nils], else: nils
        {Map.update(acc, coin, [slug], &[slug | &1]), nils}
      end)

    coins = Map.keys(slug_map)

    # Surface anything that could make Hyperliquid reject a subscribe frame or
    # that indicates a bad row on this environment only.
    bad_coins = Enum.reject(coins, &valid_coin?/1)

    if bad_coins != [] do
      Logger.warning("[HyperliquidBboWS] invalid coins in mappings: #{inspect(bad_coins)}")
    end

    if nil_slug_coins != [] do
      Logger.warning(
        "[HyperliquidBboWS] #{length(nil_slug_coins)} mapping row(s) with no sanbase slug (project/non_crypto_asset missing or hidden): " <>
          "coins=#{inspect(Enum.take(Enum.sort(nil_slug_coins), 30))}"
      )
    end

    Logger.info("[HyperliquidBboWS] mappings loaded rows=#{length(rows)} coins=#{length(coins)}")

    {MapSet.new(coins), slug_map}
  end

  # A coin must be a non-empty, whitespace-free string for Hyperliquid to
  # accept the subscribe frame; anything else is a bad mapping row.
  defp valid_coin?(c) when is_binary(c), do: c != "" and String.trim(c) == c
  defp valid_coin?(_), do: false

  # Coin universe audit

  @doc ~s"""
  Cross-check the coins we would subscribe to against Hyperliquid's live
  universe. Only Hyperliquid can say whether a coin is real, so this fetches
  the perp `meta` and `spotMeta` from `#{@info_url}` and reports every desired
  coin that Hyperliquid does not know about — the authoritative "bad coin"
  list.

  Safe to run from a remote console:

      Sanbase.Hyperliquid.Bbo.WebsocketScraper.audit_coins()

  Returns `%{desired: n, universe: n, unsupported: [coin, ...]}`, or
  `{:error, reason}` if the universe could not be fetched.
  """
  def audit_coins(desired \\ nil) do
    desired =
      (desired || elem(load_mappings(), 0))
      |> MapSet.new()
      |> MapSet.to_list()
      |> Enum.filter(&valid_coin?/1)

    case fetch_universe() do
      {:ok, universe} ->
        unsupported = desired |> Enum.reject(&MapSet.member?(universe, &1)) |> Enum.sort()

        if unsupported == [] do
          Logger.info(
            "[HyperliquidBboWS] coin audit OK — all #{length(desired)} coins present in HL universe (size=#{MapSet.size(universe)})"
          )
        else
          Logger.warning(
            "[HyperliquidBboWS] coin audit — #{length(unsupported)}/#{length(desired)} coin(s) NOT in HL universe (size=#{MapSet.size(universe)}): #{inspect(unsupported)}"
          )
        end

        %{desired: length(desired), universe: MapSet.size(universe), unsupported: unsupported}

      {:error, reason} = error ->
        Logger.warning(
          "[HyperliquidBboWS] coin audit failed to fetch HL universe: #{inspect(reason)}"
        )

        error
    end
  end

  @doc ~s"""
  Verify a single coin against Hyperliquid's live universe, bounded by
  `timeout` ms. Meant for the mapping-creation path, where only Hyperliquid
  can say whether a coin is real.

  Returns:
    * `:ok` — coin exists in the HL universe.
    * `:unsupported` — HL was reached and does not know this coin.
    * `:unverified` — HL could not be reached in time (timeout / fetch error);
      caller should allow the write but warn.
  """
  @spec coin_supported?(String.t(), non_neg_integer()) :: :ok | :unsupported | :unverified
  def coin_supported?(coin, timeout \\ @verify_timeout) when is_binary(coin) do
    task = Task.async(fn -> fetch_universe() end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {:ok, universe}} -> if MapSet.member?(universe, coin), do: :ok, else: :unsupported
      _ -> :unverified
    end
  end

  # Union of perp coin names (`meta.universe`) and spot names + token names
  # (`spotMeta.universe`/`spotMeta.tokens`), covering every `coin` form the
  # bbo channel accepts. If one request fails we still return whatever the
  # other returned so the audit stays useful.
  defp fetch_universe() do
    perp = info_request(%{type: "meta"})
    spot = info_request(%{type: "spotMeta"})

    perp_names =
      case perp do
        {:ok, body} -> universe_names(body)
        _ -> []
      end

    spot_names =
      case spot do
        {:ok, body} -> universe_names(body) ++ token_names(body)
        _ -> []
      end

    case {perp, spot} do
      {{:error, reason}, {:error, _}} -> {:error, reason}
      _ -> {:ok, MapSet.new(perp_names ++ spot_names)}
    end
  end

  defp info_request(payload) do
    case Req.post(@info_url, json: payload, receive_timeout: 10_000, retry: :transient) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %Req.Response{status: status, body: body}} -> {:error, {:http_status, status, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp universe_names(%{"universe" => universe}) when is_list(universe) do
    for %{"name" => name} <- universe, is_binary(name), do: name
  end

  defp universe_names(_), do: []

  defp token_names(%{"tokens" => tokens}) when is_list(tokens) do
    for %{"name" => name} <- tokens, is_binary(name), do: name
  end

  defp token_names(_), do: []

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
