defmodule Sanbase.Cryptocompare.HTTPHeaderUtilsTest do
  use ExUnit.Case, async: true

  alias Sanbase.Cryptocompare.HTTPHeaderUtils

  doctest Sanbase.Cryptocompare.HTTPHeaderUtils

  # value before `;window=` in Remaining-All is the remaining request count,
  # in Reset-All it is the seconds until that window resets.
  defp resp(remaining, reset) do
    headers =
      [{"X-RateLimit-Remaining-All", remaining}] ++
        if reset, do: [{"X-RateLimit-Reset-All", reset}], else: []

    %HTTPoison.Response{status_code: 200, body: "", headers: headers}
  end

  @reset "100, 1;window=1, 30;window=60, 2000;window=3600, 80000;window=86400, 1200000;window=2592000"

  describe "rate_limit_reset_seconds/1" do
    test "returns nil when not rate limited" do
      remaining =
        "100, 9500;window=1, 9500;window=60, 9500;window=3600, 38673;window=86400, 1220397;window=2592000"

      assert HTTPHeaderUtils.rate_limit_reset_seconds(resp(remaining, @reset)) == nil
    end

    test "waits for the exhausted short window, not the longest overall window" do
      # only the per-second window is exhausted -> wait 1s (its reset), not the
      # ~14 day monthly reset that get_biggest_ratelimited_window/1 would return.
      remaining =
        "100, 0;window=1, 50;window=60, 1000;window=3600, 5000;window=86400, 99999;window=2592000"

      assert HTTPHeaderUtils.rate_limit_reset_seconds(resp(remaining, @reset)) == 1
      # contrast with the pre-existing function that ignores which window is exhausted
      assert HTTPHeaderUtils.get_biggest_ratelimited_window(resp(remaining, @reset)) == 1_200_000
    end

    test "uses the reset of the exhausted window" do
      remaining =
        "100, 5;window=1, 5;window=60, 0;window=3600, 5000;window=86400, 99999;window=2592000"

      assert HTTPHeaderUtils.rate_limit_reset_seconds(resp(remaining, @reset)) == 2000
    end

    test "picks the longest exhausted window when several are exhausted" do
      remaining =
        "100, 0;window=1, 0;window=60, 0;window=3600, 5000;window=86400, 99999;window=2592000"

      assert HTTPHeaderUtils.rate_limit_reset_seconds(resp(remaining, @reset)) == 2000
    end

    test "falls back to 60s when the reset header is missing" do
      remaining =
        "100, 0;window=1, 50;window=60, 1000;window=3600, 5000;window=86400, 99999;window=2592000"

      assert HTTPHeaderUtils.rate_limit_reset_seconds(resp(remaining, nil)) == 60
    end
  end
end
