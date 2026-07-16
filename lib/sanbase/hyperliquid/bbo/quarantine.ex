defmodule Sanbase.Hyperliquid.Bbo.Quarantine do
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
      connection `#{2}` times, or HL silently ignores it. Never
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
  verdicts (~2 coins/s, a 20-coin sweep drains in ~11s). Attribution stays
  unambiguous because the kill lands within 200-300ms — always younger than
  the spacing — so a crash implicates at most one in-flight probe:

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

  # A disconnect this soon after an unconfirmed subscribe puts that coin on
  # probation as a suspect for having triggered the drop. Observed: HL kills
  # the connection within 200-300ms of the offending subscribe — every time —
  # so 1.5s is ~5x margin. At the scraper's 200ms send pacing it sweeps the
  # culprit plus ~4-6 neighbouring sends per crash, deliberately erring on
  # the side of a few extra innocents (each is cleared by a quick probe)
  # rather than ever missing the trigger.
  @suspect_window_ms 1_500
  # A probed coin that got confirmed and whose connection is still alive this
  # long after the probe subscribe is innocent. This is the floor: the kill
  # lands within 200-300ms of the subscribe, the queued frame reaches the
  # wire up to 200ms after the clock starts, and the confirmation needs a
  # round trip — below ~1s a verdict can't tell "innocent" from "kill still
  # in flight", and a wrong clearance costs a full crash.
  @probe_verdict_ms 1_000
  # A crash more than this after a probe subscribe is NOT attributed to that
  # probe — the coin keeps its probation spot, no strike. Kept tight (the
  # kill lands in 200-300ms) so random infra drops can't rack up false
  # strikes, and equal to @probe_spacing_ms so a crash implicates AT MOST ONE
  # in-flight probe even with pipelining.
  @probe_strike_window_ms 500
  # Minimum gap between consecutive probe starts. Probes are pipelined — a
  # new one starts every spacing while earlier ones await verdicts — so a
  # probation sweep drains at ~2 coins/s (20 coins in ~11s). Must exceed the
  # observed 200-300ms kill lag so a crash points at exactly one probe.
  @probe_spacing_ms 500
  # Probe crashes before conviction; see moduledoc.
  @probe_strikes_to_convict 2
  # Don't start a probe until the connection has been up this long with an
  # empty outbound queue, so the verdict isn't polluted by startup churn.
  @probe_min_uptime_ms 10_000
  # How many recently-sent subscribe frames to remember as crash evidence.
  # MUST cover @suspect_window_ms at the scraper's 200ms send pacing — a
  # culprit that falls off this list before the crash is never caught.
  # 10 entries = 2s of sends, above the window.
  @recent_sends_size 10

  defstruct probation: [],
            # In-flight probes, newest first — [%{coin: _, started_ms: _}].
            probing: [],
            probe_strikes: %{},
            quarantined: %{},
            audit_excluded: %{},
            # Crash evidence: the last @recent_sends_size subscribe frames the
            # scraper actually sent on the CURRENT connection, newest first —
            # %{coin: _, slugs: _, sent_at_ms: _}. Fed by track_send/4, reset
            # by on_connect/1, consumed by handle_crash/3.
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
    %{q | recent_sends: Enum.take([entry | q.recent_sends], @recent_sends_size)}
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
    # Resolve every probe whose verdict window has elapsed (probes pipeline,
    # so several can come due together), then start the next probe if the
    # spacing since the newest in-flight one has passed.
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

  # The crash's verdict on the in-flight probes. Only a probe younger than
  # @probe_strike_window_ms is blamed — at most one, since probes start
  # @probe_spacing_ms apart. Older unresolved probes just fall back to
  # probation (they keep their spot, no strike) and get re-probed. A struck
  # coin is convicted at @probe_strikes_to_convict, otherwise it moves to the
  # END of probation so the other suspects get their probe before its retry.
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

  # The connection survived @probe_verdict_ms after the probe subscribe.
  # Confirmed -> innocent, back to normal subscriptions (it is already
  # subscribed and streaming; reconcile keeps it). Never confirmed -> HL
  # silently ignores this coin ("bbo" only accepts tradeable pair names);
  # quarantine it so we stop re-sending a subscribe HL won't answer.
  # The caller has already dropped the probe from `probing`.
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

  # Starts the next probe when it can produce a clean verdict: connection
  # settled, and at least @probe_spacing_ms since the newest in-flight probe.
  # A coin stays in probation until its verdict; `probing` marks it in flight.
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
