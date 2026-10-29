defmodule Sanbase.ExternalServices.Coinmarketcap.UtilsTest do
  use ExUnit.Case, async: true

  alias Sanbase.ExternalServices.Coinmarketcap.Utils

  test "retry-after with seconds" do
    datetime = Utils.retry_after_datetime(%Tesla.Env{headers: [{"retry-after", "120"}]})
    assert_in_delta DateTime.diff(datetime, DateTime.utc_now()), 120, 2
  end

  test "retry-after with an HTTP-date" do
    datetime =
      Utils.retry_after_datetime(%Tesla.Env{
        headers: [{"retry-after", "Wed, 21 Oct 2026 07:28:00 GMT"}]
      })

    assert DateTime.compare(datetime, ~U[2026-10-21 07:28:00Z]) == :eq
  end

  test "missing or invalid retry-after defaults to 1 second" do
    for headers <- [[], [{"retry-after", "soon"}]] do
      datetime = Utils.retry_after_datetime(%Tesla.Env{headers: headers})
      assert_in_delta DateTime.diff(datetime, DateTime.utc_now()), 1, 1
    end
  end
end
