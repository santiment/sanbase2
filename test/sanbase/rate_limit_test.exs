defmodule Sanbase.RateLimitTest do
  # Sanbase.RateLimit wraps Hammer 7.x with an ETS backend.
  #
  # The API is: Sanbase.RateLimit.hit(bucket, scale, limit)
  #   - bucket: a string key identifying the rate limiter (e.g. "telegram_bot")
  #   - scale: the time window in milliseconds (e.g. 1000 = allow `limit` requests per 1 second)
  #   - limit: the maximum number of requests allowed within that window
  #
  # Returns {:allow, count} when under the limit, or {:deny, wait_period_ms} when exceeded.
  use ExUnit.Case, async: false

  setup do
    {:ok, bucket: "test_bucket_#{System.unique_integer([:positive])}"}
  end

  test "allows requests within the limit", %{bucket: bucket} do
    # Allow up to 5 requests per 1-second window
    assert {:allow, 1} = Sanbase.RateLimit.hit(bucket, 1000, 5)
    assert {:allow, 2} = Sanbase.RateLimit.hit(bucket, 1000, 5)
    assert {:allow, 3} = Sanbase.RateLimit.hit(bucket, 1000, 5)
  end

  test "denies requests exceeding the limit", %{bucket: bucket} do
    # Allow up to 3 requests per 1-second window
    scale = 1000
    limit = 3

    assert {:allow, 1} = Sanbase.RateLimit.hit(bucket, scale, limit)
    assert {:allow, 2} = Sanbase.RateLimit.hit(bucket, scale, limit)
    assert {:allow, 3} = Sanbase.RateLimit.hit(bucket, scale, limit)

    # 4th request exceeds the limit — returns {:deny, ms_until_window_resets}
    assert {:deny, wait_period} = Sanbase.RateLimit.hit(bucket, scale, limit)
    assert is_integer(wait_period) and wait_period > 0
  end

  test "different buckets are tracked independently", %{bucket: bucket} do
    bucket_a = "#{bucket}_a"
    bucket_b = "#{bucket}_b"
    # Allow up to 2 requests per 1-second window
    scale = 1000
    limit = 2

    # Exhaust bucket_a
    assert {:allow, 1} = Sanbase.RateLimit.hit(bucket_a, scale, limit)
    assert {:allow, 2} = Sanbase.RateLimit.hit(bucket_a, scale, limit)
    assert {:deny, _} = Sanbase.RateLimit.hit(bucket_a, scale, limit)

    # bucket_b is unaffected — it has its own counter
    assert {:allow, 1} = Sanbase.RateLimit.hit(bucket_b, scale, limit)
    assert {:allow, 2} = Sanbase.RateLimit.hit(bucket_b, scale, limit)
  end

  test "rate limit resets after the window expires", %{bucket: bucket} do
    # Allow 1 request per 100ms window
    scale = 100
    limit = 1

    assert {:allow, 1} = Sanbase.RateLimit.hit(bucket, scale, limit)
    assert {:deny, _} = Sanbase.RateLimit.hit(bucket, scale, limit)

    # Wait for the window to expire, then the counter resets
    Process.sleep(scale + 10)

    assert {:allow, 1} = Sanbase.RateLimit.hit(bucket, scale, limit)
  end
end
