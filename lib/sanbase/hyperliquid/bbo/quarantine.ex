defmodule Sanbase.Hyperliquid.Bbo.Quarantine do
  # Declared before @moduledoc so the docs can interpolate it.
  @probe_strikes_to_convict 2

  @moduledoc ~s"""
  Coin discipline for the Hyperliquid BBO scraper: which coins must not be
  subscribed, why, and the probation → probe → verdict workflow that decides
  it. Pure data and functions — the `WebsocketScraper` process keeps one
  struct in its state and calls in on connection events; nothing here talks
  to the network or spawns processes.

  ## Why this exists

  Hyperliquid reacts to a subscribe it dislikes in one of two ways: it
  silently ignores the frame (no `subscriptionResponse`), or it drops the
  whole TCP connection — killing the stream for every other coin. Without
  discipline, every reconnect re-subscribes the trigger and dies again.

  ## Exclusion sources (all `%{coin => reason}`)

    * `audit_excluded` — verdicts of the latest `CoinUniverse.audit/0`
      (unknown to HL, spot-token-only, ...). Replaced wholesale via
      `apply_audit/2` so a coin HL re-lists recovers automatically.
    * `quarantined` — probe convictions: the coin's solo subscribe killed the
      connection `#{@probe_strikes_to_convict}` times, or HL silently ignores it. Never
      auto-refreshed; a process restart clears it.
    * `ignored_coins/0` — operator escape hatch via the
      `HYPERLIQUID_IGNORED_COINS` env var (comma-separated coin names).

  `excluded/1` merges all three; the scraper's reconcile skips (and
  unsubscribes) every coin in it.

  ## Probation → probe → verdict

  A crash puts every unconfirmed subscribe sent within `@suspect_window_ms`
  of death on `probation` (`handle_crash/3`) — the whole window, not just the
  newest send, because the TCP drop can lag the offending subscribe by a few
  pacing ticks, letting innocent frames go out after it. Probation coins are
  excluded from bulk subscribing and re-tried by probes (`probe_tick/5`) on a
  settled connection. Probes are PIPELINED: a new probe starts every
  `@probe_spacing_ms` while earlier ones await their `@probe_verdict_ms`
  verdicts (~1 coin per 1.6s, a typical 5-8 coin sweep drains in ~10s).
  Attribution stays unambiguous because the strike window is strictly smaller
  than the spacing, so a crash implicates at most one in-flight probe:

    * crash within `@probe_strike_window_ms` of the probe → a strike; at
      `@probe_strikes_to_convict` strikes the coin is quarantined (two, so a
      coincidental infra drop can't convict). After a first strike the coin
      goes to the END of probation so other suspects get probed before its
      retry.
    * confirmed and alive `@probe_verdict_ms` after the probe → innocent,
      cleared back to normal subscriptions.
    * never confirmed but the connection lives → HL silently ignores the
      coin; quarantined so we stop re-sending a subscribe HL won't answer.
  """

  require Logger

  alias Sanbase.Utils.Config

  # A disconnect this soon after an unconfirmed subscribe makes that coin a suspect. HL
  # kills within 200-300ms of the offending subscribe, so 1.5s is ~5x margin. At 200ms
  # pacing it sweeps the culprit plus ~4-6 neighbours, each cleared by a probe.
  @suspect_window_ms 1_500
  # A confirmed probe whose connection is still alive this long after its subscribe hit
  # the wire is innocent. Must exceed @probe_strike_window_ms, or a coin could be cleared
  # while a kill could still be its.
  @probe_verdict_ms 2_000
  # A crash within this window after a probe subscribe is that probe's strike; later ones
  # are infra noise. Kill lag is 200-300ms but jitters - kills near 500ms went
  # unattributed and left strike counts below conviction, hence the margin. Strictly less
  # than @probe_spacing_ms, so a boundary crash cannot blame two in-flight probes.
  @probe_strike_window_ms 1_500
  # Minimum gap between probe starts. Probes pipeline, so probation drains at ~1 coin per
  # 1.6s. Must exceed @probe_strike_window_ms, or one crash implicates several probes.
  @probe_spacing_ms 1_600
  # Uptime with an empty outbound queue required before a probe, against startup churn.
  @probe_min_uptime_ms 10_000
  # Recently-sent subscribe frames kept as crash evidence. MUST cover @suspect_window_ms
  # at the scraper's 200ms pacing, else the culprit falls off the list before the crash.
  @recent_sends_size 10

  defstruct probation: [],
            # In-flight probes, newest first — [%{coin: _, started_ms: _}].
            probing: [],
            probe_strikes: %{},
            quarantined: %{},
            audit_excluded: %{},
            # Crash evidence: the last @recent_sends_size subscribe frames of the CURRENT
            # connection, newest first. Fed by track_send/4, reset by on_connect/1.
            recent_sends: []

  @type t :: %__MODULE__{}
  @type coin :: String.t()
  @type reason :: String.t()

  @spec new() :: t()
  def new(), do: %__MODULE__{}

  @doc ~s"""
  Whether the probation/probe/conviction workflow is active, from the
  `HYPERLIQUID_QUARANTINE_ENABLED` env var. Enabled unless explicitly set to
  `false`/`0`. When disabled, crashes add no suspects, no probes run and
  nothing new is quarantined — but the audit exclusions and the
  `HYPERLIQUID_IGNORED_COINS` list still apply (they are separate features
  that only share the `excluded/1` merge).
  """
  @spec enabled?() :: boolean()
  def enabled?() do
    Config.module_get(__MODULE__, :enabled?, "true")
    |> Config.parse_boolean_value()
    |> Kernel.!=(false)
  end

  @doc "How close to a disconnect a subscribe must be to count as a suspect."
  @spec suspect_window_ms() :: pos_integer()
  def suspect_window_ms(), do: @suspect_window_ms

  @doc ~s"""
  Everything that must not be subscribed, as `%{coin => reason}`: env-ignored
  coins, the latest audit verdicts, probe convictions (later sources win the
  reason on overlap).
  """
  @spec excluded(t()) :: %{coin() => reason()}
  def excluded(%__MODULE__{} = q) do
    ignored_coins()
    |> Map.merge(q.audit_excluded)
    |> Map.merge(q.quarantined)
  end

  @doc "Coins awaiting an individual probe, head probed first."
  @spec probation(t()) :: [coin()]
  def probation(%__MODULE__{} = q), do: q.probation

  @doc "Coins whose probes are in flight, newest first (empty when idle)."
  @spec probing_coins(t()) :: [coin()]
  def probing_coins(%__MODULE__{} = q), do: Enum.map(q.probing, & &1.coin)

  @doc ~s"""
  Record a subscribe frame the scraper just sent (crash evidence, newest
  first, capped at #{@recent_sends_size}). Slugs are resolved by the caller
  at send time — the slug map may differ by crash time.
  """
  @spec track_send(t(), coin(), [String.t()], integer()) :: t()
  def track_send(%__MODULE__{} = q, coin, slugs, now) do
    entry = %{coin: coin, slugs: slugs, sent_at_ms: now}

    # The strike/verdict clock restarts when the frame reaches the wire. started_ms is set
    # at QUEUE time, but flush pacing can burn 200ms before the send - on top of a kill lag
    # already near the strike window, real kills would go unattributed.
    probing =
      Enum.map(q.probing, fn
        %{coin: ^coin} = probe -> %{probe | started_ms: now}
        probe -> probe
      end)

    %{
      q
      | probing: probing,
        recent_sends: Enum.take([entry | q.recent_sends], @recent_sends_size)
    }
  end

  @doc "Reset the per-connection crash evidence; call on every (re)connect."
  @spec on_connect(t()) :: t()
  def on_connect(%__MODULE__{} = q), do: %{q | recent_sends: []}

  @doc ~s"""
  The newest `limit` tracked sends as one log-friendly string — if a
  disconnect consistently follows the same coin/slug with a small ms_ago,
  that subscription is the trigger.
  """
  @spec recent_sends_summary(t(), integer(), pos_integer()) :: String.t()
  def recent_sends_summary(%__MODULE__{} = q, now, limit \\ 5) do
    q.recent_sends
    |> Enum.take(limit)
    |> Enum.map_join(", ", fn %{coin: coin, slugs: slugs, sent_at_ms: at} ->
      "#{coin}=#{Enum.join(slugs, "|")} #{now - at}ms_ago"
    end)
  end

  @doc ~s"""
  Operator-managed ignore list from the `HYPERLIQUID_IGNORED_COINS` env var
  (comma-separated coin names), as `%{coin => reason}`.
  """
  @spec ignored_coins() :: %{coin() => reason()}
  def ignored_coins() do
    Config.module_get(__MODULE__, :ignored_coins)
    |> to_string()
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Map.new(&{&1, "ignored via HYPERLIQUID_IGNORED_COINS"})
  end

  @doc ~s"""
  Crash forensics, called on every real disconnect (not on failed reconnect
  attempts) BEFORE the scraper clears its connection state. Resolves the
  in-flight probes (the crash is the young one's verdict — a strike,
  convicting at #{@probe_strikes_to_convict}) and puts every unconfirmed
  subscribe from `recent_sends` within #{@suspect_window_ms}ms of death on
  probation. `active_subs` are the confirmed coins — confirmed means
  innocent.
  """
  @spec handle_crash(t(), MapSet.t(coin()), integer()) :: t()
  def handle_crash(%__MODULE__{} = q, active_subs, now) do
    if enabled?() do
      q = resolve_probe_crash(q, now)

      suspects =
        q.recent_sends
        |> Enum.filter(fn %{sent_at_ms: at} -> now - at <= @suspect_window_ms end)
        |> Enum.map(& &1.coin)
        |> Enum.reject(&MapSet.member?(active_subs, &1))

      probate(
        q,
        suspects,
        "unconfirmed subscribe(s) sent <#{@suspect_window_ms}ms before the disconnect"
      )
    else
      q
    end
  end

  @doc ~s"""
  Put `coins` on probation (skipping ones already there or excluded), logging
  `why`. Probation coins are excluded from bulk subscribing and re-tried one
  at a time by `probe_tick/5`.
  """
  @spec probate(t(), [coin()], String.t()) :: t()
  def probate(%__MODULE__{} = q, coins, why) do
    excluded = excluded(q)

    new_coins =
      coins
      |> Enum.uniq()
      |> Enum.reject(fn coin -> coin in q.probation or Map.has_key?(excluded, coin) end)

    if new_coins == [] or not enabled?() do
      q
    else
      Logger.warning(
        "[HyperliquidQuarantine] probation += #{inspect(new_coins)} — #{why}; " <>
          "each will be probed individually"
      )

      %{q | probation: q.probation ++ new_coins}
    end
  end

  @doc ~s"""
  Apply an audit verdict: REPLACES (never merges) `audit_excluded` so a coin
  HL re-lists recovers automatically; coins the audit condemned leave
  probation too — the audit's reason beats a probe verdict.
  """
  @spec apply_audit(t(), %{coin() => reason()}) :: t()
  def apply_audit(%__MODULE__{} = q, reasons) when is_map(reasons) do
    if map_size(reasons) > 0 do
      Logger.warning(
        "[HyperliquidQuarantine] audit excluded #{map_size(reasons)} coin(s): #{inspect(reasons)}"
      )
    end

    %{
      q
      | audit_excluded: reasons,
        probation: Enum.reject(q.probation, &Map.has_key?(reasons, &1))
    }
  end

  @doc ~s"""
  The probe worker step, called on the scraper's `:probe_next` tick. Either
  resolves the in-flight probe's survival verdict (crash verdicts arrive via
  `handle_crash/3`) or, when the connection is settled — up at least
  #{@probe_min_uptime_ms}ms with an empty outbound queue — starts the next
  probe. Returns `{q, {:subscribe, coin} | :noop}`; the scraper queues the
  subscribe frame.
  """
  @spec probe_tick(t(), MapSet.t(coin()), non_neg_integer(), boolean(), integer()) ::
          {t(), {:subscribe, coin()} | :noop}
  def probe_tick(%__MODULE__{} = q, active_subs, uptime_ms, queue_empty?, now) do
    if enabled?(),
      do: do_probe_tick(q, active_subs, uptime_ms, queue_empty?, now),
      else: {q, :noop}
  end

  defp do_probe_tick(%__MODULE__{} = q, active_subs, uptime_ms, queue_empty?, now) do
    # Resolve every probe whose verdict window elapsed (several can come due together),
    # then start the next one if the spacing since the newest in-flight has passed.
    {due, in_flight} =
      Enum.split_with(q.probing, fn %{started_ms: started} ->
        now - started >= @probe_verdict_ms
      end)

    q =
      Enum.reduce(due, %{q | probing: in_flight}, fn %{coin: coin}, acc ->
        resolve_probe_survival(acc, coin, active_subs)
      end)

    maybe_start_probe(q, uptime_ms, queue_empty?, now)
  end

  # Only a probe younger than @probe_strike_window_ms is blamed - at most one, since
  # probes start @probe_spacing_ms apart. Older unresolved probes fall back to probation
  # and are re-probed. A struck coin is convicted at @probe_strikes_to_convict, else it
  # moves to the END of probation so the other suspects are probed before its retry.
  defp resolve_probe_crash(%__MODULE__{} = q, now) do
    guilty =
      Enum.filter(q.probing, fn %{started_ms: started} ->
        now - started <= @probe_strike_window_ms
      end)

    Enum.reduce(guilty, %{q | probing: []}, fn %{coin: coin, started_ms: started}, acc ->
      strike(acc, coin, now - started)
    end)
  end

  defp strike(%__MODULE__{} = q, coin, age_ms) do
    strikes = Map.update(q.probe_strikes, coin, 1, &(&1 + 1))
    count = Map.fetch!(strikes, coin)

    if count >= @probe_strikes_to_convict do
      %{q | probe_strikes: Map.delete(strikes, coin), probation: List.delete(q.probation, coin)}
      |> quarantine(
        coin,
        "probe conviction — connection died #{age_ms}ms after its subscribe " <>
          "(strike #{count}/#{@probe_strikes_to_convict})"
      )
    else
      Logger.warning(
        "[HyperliquidQuarantine] probe strike coin=#{coin} — connection died " <>
          "#{age_ms}ms after its probe subscribe " <>
          "(strike #{count}/#{@probe_strikes_to_convict}); will re-probe"
      )

      %{
        q
        | probe_strikes: strikes,
          probation: List.delete(q.probation, coin) ++ [coin]
      }
    end
  end

  # The connection survived @probe_verdict_ms after the probe subscribe. Confirmed means
  # innocent and already streaming. Never confirmed means HL silently ignores this coin
  # ("bbo" only accepts tradeable pair names), so quarantine it.
  defp resolve_probe_survival(%__MODULE__{} = q, coin, active_subs) do
    q = %{q | probation: List.delete(q.probation, coin)}

    if MapSet.member?(active_subs, coin) do
      Logger.info(
        "[HyperliquidQuarantine] probe cleared coin=#{coin} — confirmed and the connection " <>
          "survived #{@probe_verdict_ms}ms; back to normal subscriptions"
      )

      %{q | probe_strikes: Map.delete(q.probe_strikes, coin)}
    else
      quarantine(q, coin, "probe never confirmed — HL silently ignores its subscribe")
    end
  end

  # Starts the next probe only when it can produce a clean verdict: connection settled and
  # @probe_spacing_ms since the newest in-flight one. `probing` marks a coin in flight.
  defp maybe_start_probe(%__MODULE__{} = q, uptime_ms, true = _queue_empty?, now)
       when uptime_ms >= @probe_min_uptime_ms do
    in_flight = probing_coins(q)

    spacing_ok? =
      case q.probing do
        [] -> true
        [%{started_ms: newest} | _] -> now - newest >= @probe_spacing_ms
      end

    case {spacing_ok?, Enum.find(q.probation, &(&1 not in in_flight))} do
      {true, coin} when is_binary(coin) ->
        Logger.info(
          "[HyperliquidQuarantine] probing coin=#{coin} " <>
            "strikes=#{Map.get(q.probe_strikes, coin, 0)}/#{@probe_strikes_to_convict} " <>
            "in_flight=#{length(q.probing) + 1} probation_left=#{length(q.probation)}"
        )

        {%{q | probing: [%{coin: coin, started_ms: now} | q.probing]}, {:subscribe, coin}}

      _ ->
        {q, :noop}
    end
  end

  defp maybe_start_probe(%__MODULE__{} = q, _uptime_ms, _queue_empty?, _now), do: {q, :noop}

  defp quarantine(%__MODULE__{} = q, coin, reason) do
    Logger.warning(
      "[HyperliquidQuarantine] quarantining coin=#{coin} — #{reason}; " <>
        "excluded until process restart"
    )

    %{q | quarantined: Map.put(q.quarantined, coin, reason)}
  end
end
