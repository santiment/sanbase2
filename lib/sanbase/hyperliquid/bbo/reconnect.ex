defmodule Sanbase.Hyperliquid.Bbo.Reconnect do
  @moduledoc ~s"""
  Reconnect policy for the Hyperliquid BBO websocket: the backoff ladder, the
  jitter that de-syncs instances sharing an egress IP, the rolling count of
  our own connects (HL allows 30 new connections/min per IP, aggregated over
  every client behind it), and the wording of disconnect causes. Pure
  functions — the `WebsocketScraper` process keeps the backoff value and
  connect timestamps in its state and calls in around connect/disconnect.

  The ladder is gentle on purpose (x#{1.1} per consecutive disconnect):
  bad-coin crash loops are handled by `Quarantine`, so the backoff only
  guards infra churn and should recover fast. Only a connection that
  survived the stability threshold restarts the ladder — a remote that
  drops us seconds after connect keeps it climbing, so we slow down instead
  of locking the IP over its limits with a reconnect storm.
  """

  # First reconnect delay; grows x@backoff_factor per consecutive disconnect.
  @initial_ms 1_000
  # Growth factor per consecutive disconnect.
  @backoff_factor 1.1
  # Hard ceiling on a single reconnect sleep, jitter included.
  @max_ms 20_000
  # A connection must live this long before the next disconnect starts the
  # ladder over from @initial_ms; anything shorter keeps climbing.
  @stable_connection_ms 60_000
  # Cap on the random jitter added to each reconnect sleep.
  @jitter_max_ms 1_000
  # The growing part of the backoff caps here so base + jitter never
  # exceeds @max_ms.
  @base_cap_ms @max_ms - @jitter_max_ms
  # Rolling window for counting our own connects, matching the window of
  # HL's "30 new connections per minute per IP" limit.
  @connects_window_ms 60_000

  @doc "The backoff a fresh process starts from."
  def initial_backoff_ms(), do: @initial_ms

  @doc ~s"""
  The reconnect schedule after a disconnect: `{sleep_base_ms, next_backoff_ms}`.
  `sleep_base_ms` is slept now (plus `jitter_ms/1`); `next_backoff_ms` is
  stored for the disconnect after this one, so the ladder climbs
  x#{@backoff_factor} per step up to #{@base_cap_ms}ms. Only a dropped live
  connection (attempt == 1) that survived #{@stable_connection_ms}ms restarts
  the ladder; short-lived connections and failed reconnect attempts
  (attempt > 1, where lifetime_ms is nil) keep climbing.
  """
  def plan(current_backoff_ms, lifetime_ms, attempt) do
    stable? = attempt == 1 and is_integer(lifetime_ms) and lifetime_ms >= @stable_connection_ms

    base_ms =
      if stable?,
        do: @initial_ms,
        else: min(current_backoff_ms, @base_cap_ms)

    {base_ms, min(ceil(base_ms * @backoff_factor), @base_cap_ms)}
  end

  @doc ~s"""
  Random jitter to add to a reconnect sleep — proportional to the backoff so
  a healthy single reconnect stays fast, and bounded so base + jitter never
  exceeds #{@max_ms}ms.
  """
  def jitter_ms(base_ms), do: :rand.uniform(min(base_ms, @jitter_max_ms))

  @doc ~s"""
  Prepend this connect's timestamp and drop entries older than the rolling
  #{@connects_window_ms}ms window — the count is compared against HL's
  30 new connections/min/IP limit in the connect log.
  """
  def track_connect(connect_times, now) do
    [now | connect_times]
    |> Enum.take_while(&(now - &1 < @connects_window_ms))
  end

  @doc ~s"""
  The remote's stated reason for a drop, in words. `{:remote, :closed}` is an
  abrupt TCP close with NO WebSocket close frame — the remote never said why;
  no more detail exists on the wire. HL/CloudFront drop connections this way
  when per-IP limits are exceeded (10 concurrent conns, 30 new conns/min,
  2000 client msgs/min, 1000 subs — aggregated over every client behind the
  IP), so persistent short lifetimes with this cause usually mean IP-level
  rate limiting rather than an app error.
  """
  def describe_cause({:remote, :closed}),
    do: "remote dropped TCP without a close frame (no reason on wire; rate-limit/infra style)"

  def describe_cause({:remote, code, msg}),
    do: "remote sent close frame code=#{inspect(code)} msg=#{inspect(msg)}"

  def describe_cause({:local, reason}), do: "closed by our side: #{inspect(reason)}"
  def describe_cause(other), do: inspect(other)
end
