defmodule Sanbase.SocialData.MetricAdapterTest do
  use SanbaseWeb.ConnCase, async: true

  alias Sanbase.SocialData.MetricAdapter

  describe "first_datetime/3" do
    test "for metrics with a source suffix" do
      assert MetricAdapter.first_datetime("social_volume_telegram", %{text: "btc"}, []) ==
               {:ok, ~U[2016-03-29 00:00:00Z]}

      assert MetricAdapter.first_datetime("sentiment_positive_reddit", %{text: "btc"}, []) ==
               {:ok, ~U[2016-01-01 00:00:00Z]}

      assert MetricAdapter.first_datetime("social_dominance_total", %{text: "btc"}, []) ==
               {:ok, ~U[2011-06-01 00:00:00Z]}
    end

    test "for farcaster metrics" do
      assert MetricAdapter.first_datetime("social_volume_farcaster", %{text: "btc"}, []) ==
               {:ok, ~U[2024-01-01 00:00:00Z]}

      assert MetricAdapter.first_datetime("sentiment_balance_farcaster", %{text: "btc"}, []) ==
               {:ok, ~U[2024-01-01 00:00:00Z]}
    end

    test "for social_active_users" do
      assert MetricAdapter.first_datetime("social_active_users", %{source: "telegram"}, []) ==
               {:ok, ~U[2016-03-29 00:00:00Z]}

      assert MetricAdapter.first_datetime("social_active_users", %{source: "twitter_crypto"}, []) ==
               {:ok, ~U[2018-02-13 00:00:00Z]}
    end

    test "for social_active_users without a source returns an error" do
      assert {:error, error} = MetricAdapter.first_datetime("social_active_users", %{}, [])
      assert error =~ "must have a source"
    end

    test "for an unknown source returns an error instead of raising" do
      assert {:error, error} =
               MetricAdapter.first_datetime("social_active_users", %{source: "myspace"}, [])

      assert error =~ "does not have a first datetime defined"
    end
  end
end
