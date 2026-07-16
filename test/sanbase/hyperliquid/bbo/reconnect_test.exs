defmodule Sanbase.Hyperliquid.Bbo.ReconnectTest do
  use ExUnit.Case, async: true

  alias Sanbase.Hyperliquid.Bbo.Reconnect

  # The stable-reset paths are tested here because the scraper's
  # handle_disconnect/2 sleeps its result for real — the reset branch would
  # block the suite for the initial backoff (1s) plus jitter per test.
  describe "plan/3" do
    test "connection that lived past the stable threshold restarts the ladder" do
      assert {1_000, 1_100} = Reconnect.plan(16_000, 120_000, 1)
    end

    test "short lifetime keeps climbing the ladder" do
      assert {4_000, 4_400} = Reconnect.plan(4_000, 3_000, 1)
    end

    test "failed reconnect attempt (attempt_number > 1) never restarts the ladder" do
      assert {4_000, 4_400} = Reconnect.plan(4_000, 120_000, 2)
    end

    test "nil lifetime (no live connection was dropped) keeps climbing" do
      assert {4_000, 4_400} = Reconnect.plan(4_000, nil, 1)
    end

    test "sleep base plus max jitter never exceeds the 20s ceiling" do
      {base, next} = Reconnect.plan(1_000_000, 3_000, 1)
      assert base + 1_000 <= 20_000
      assert next + 1_000 <= 20_000
    end
  end

  describe "jitter_ms/1" do
    test "is positive and bounded by min(base, cap)" do
      for _ <- 1..50 do
        assert Reconnect.jitter_ms(100) in 1..100
        assert Reconnect.jitter_ms(50_000) in 1..1_000
      end
    end
  end

  describe "track_connect/2" do
    test "prepends now and drops entries older than the rolling minute" do
      now = 1_000_000
      times = [now - 30_000, now - 59_999, now - 60_000, now - 90_000]

      assert Reconnect.track_connect(times, now) == [now, now - 30_000, now - 59_999]
    end
  end

  describe "describe_cause/1" do
    test "names the abrupt TCP drop" do
      assert Reconnect.describe_cause({:remote, :closed}) =~ "without a close frame"
    end

    test "surfaces close frame code and message" do
      assert Reconnect.describe_cause({:remote, 1008, "policy"}) =~ "code=1008"
    end

    test "falls back to inspect for unknown shapes" do
      assert Reconnect.describe_cause(:weird) == ":weird"
    end
  end
end
