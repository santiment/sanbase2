defmodule SanbaseWeb.Graphql.Middlewares.PublicRateLimitTest do
  # Changes the global application env.
  use ExUnit.Case, async: false

  alias Absinthe.Resolution
  alias SanbaseWeb.Graphql.Middlewares.PublicRateLimit

  setup do
    original = Application.get_env(:sanbase, PublicRateLimit)
    on_exit(fn -> Application.put_env(:sanbase, PublicRateLimit, original) end)

    # A fresh bucket per test, so counters from other tests do not count.
    bucket = :"test_bucket_#{System.unique_integer([:positive])}"
    %{bucket: bucket}
  end

  test "suggests an API key when the authenticated limit is higher", %{bucket: bucket} do
    put_windows(bucket,
      anonymous: [{1, :timer.minutes(1)}],
      authenticated: [{5, :timer.minutes(1)}]
    )

    assert run(bucket, %{remote_ip: {1, 2, 3, 4}}).state == :unresolved
    assert error(run(bucket, %{remote_ip: {1, 2, 3, 4}})) =~ "authenticate with an API key"
  end

  test "no API key advice when anonymous and authenticated limits are the same",
       %{bucket: bucket} do
    windows = [{1, :timer.minutes(1)}]
    put_windows(bucket, anonymous: windows, authenticated: windows)

    run(bucket, %{remote_ip: {1, 2, 3, 5}})
    message = error(run(bucket, %{remote_ip: {1, 2, 3, 5}}))

    assert message =~ "Rate limit exceeded. Try again in"
    refute message =~ "API key"
  end

  test "a caller without user or IP is not limited by default", %{bucket: bucket} do
    put_windows(bucket, anonymous: [{1, :timer.minutes(1)}])

    for _ <- 1..3, do: assert(run(bucket, %{}).state == :unresolved)
  end

  test "with limit_unidentified, callers without user or IP share one counter",
       %{bucket: bucket} do
    put_windows(bucket, anonymous: [{1, :timer.minutes(1)}])

    assert run(bucket, %{}, limit_unidentified: true).state == :unresolved
    assert error(run(bucket, %{}, limit_unidentified: true)) =~ "Rate limit exceeded"
  end

  defp put_windows(bucket, windows) do
    config = Application.get_env(:sanbase, PublicRateLimit, [])
    Application.put_env(:sanbase, PublicRateLimit, Keyword.put(config, bucket, windows))
  end

  defp run(bucket, context, opts \\ []) do
    PublicRateLimit.call(
      %Resolution{context: context, state: :unresolved},
      [bucket: bucket] ++ opts
    )
  end

  defp error(%Resolution{state: :resolved, errors: [message]}), do: message
end
