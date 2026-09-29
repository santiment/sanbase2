defmodule SanbaseWeb.Graphql.Middlewares.PublicRateLimit do
  @moduledoc """
  Per-caller rate limit for public (`meta(access: :free)`) queries that trigger
  paid upstream calls, such as the Academy search (OpenAI embedding + LLM rerank).

  Anonymous callers are limited per remote IP. Authenticated callers (JWT,
  API key, basic auth) are limited per user with higher limits, so evaluation
  scripts can run against prod by authenticating with an API key.

  Each caller kind has a list of `{limit, window_ms}` windows and a call must
  fit all of them: a per-minute window stops bursts, hour and day windows cap
  the LLM spend of one caller that stays just under the per-minute limit.

  Usage:

      middleware(SanbaseWeb.Graphql.Middlewares.PublicRateLimit, bucket: :academy_search)

  Limits are read from the application env on every call, so they can be
  changed at runtime (e.g. from a remote shell) without a deploy:

      config :sanbase, SanbaseWeb.Graphql.Middlewares.PublicRateLimit,
        academy_search: [
          anonymous: [{10, :timer.minutes(1)}, {100, :timer.hours(1)}],
          authenticated: [{60, :timer.minutes(1)}]
        ]

  A bucket or caller kind with no configured windows is not rate limited. The
  counters live in the node-local `Sanbase.RateLimit` ETS backend: with N pods
  the effective limit is up to N times the configured one, and a deploy resets
  them. This is an abuse guard, not a billing quota.
  """
  @behaviour Absinthe.Middleware

  require Logger

  alias Absinthe.Resolution

  @impl true
  def call(%Resolution{state: :resolved} = resolution, _opts), do: resolution

  def call(%Resolution{context: context} = resolution, opts) do
    bucket = Keyword.fetch!(opts, :bucket)

    with {kind, key} <- caller(context),
         windows when windows != [] <- windows_for(bucket, kind),
         {:deny, retry_after_ms} <- hit_all(bucket, key, windows) do
      Logger.info("[PublicRateLimit] bucket=#{bucket} caller=#{key} limited")

      Resolution.put_result(
        resolution,
        {:error,
         "Rate limit exceeded. Try again in #{format_wait(retry_after_ms)}, " <>
           "or authenticate with an API key for a higher limit."}
      )
    else
      _ -> resolution
    end
  end

  # Windows are checked shortest first and the first denial stops the check, so
  # a burst that the per-minute window rejects does not eat the daily budget.
  defp hit_all(bucket, key, windows) do
    windows
    |> Enum.sort_by(fn {_limit, window_ms} -> window_ms end)
    |> Enum.reduce_while(:allow, fn {limit, window_ms}, :allow ->
      case Sanbase.RateLimit.hit(
             "public_rate_limit:#{bucket}:#{window_ms}:#{key}",
             window_ms,
             limit
           ) do
        {:allow, _count} -> {:cont, :allow}
        {:deny, retry_after_ms} -> {:halt, {:deny, retry_after_ms}}
      end
    end)
  end

  defp caller(%{auth: %{current_user: %{id: user_id}}}), do: {:authenticated, "user:#{user_id}"}

  defp caller(%{remote_ip: remote_ip}) when is_tuple(remote_ip),
    do: {:anonymous, "ip:#{Sanbase.Utils.IP.ip_tuple_to_string(remote_ip)}"}

  defp caller(_context), do: nil

  defp windows_for(bucket, kind) do
    :sanbase
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(bucket, [])
    |> Keyword.get(kind, [])
    |> List.wrap()
  end

  defp format_wait(ms) when ms < 60_000, do: "#{ceil(ms / 1000)} seconds"
  defp format_wait(ms) when ms < 3_600_000, do: "#{ceil(ms / 60_000)} minutes"
  defp format_wait(ms), do: "#{ceil(ms / 3_600_000)} hours"
end
