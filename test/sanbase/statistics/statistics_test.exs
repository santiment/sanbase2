defmodule Sanbase.StatisticsTest do
  use Sanbase.DataCase

  import Sanbase.Factory
  import Sanbase.TestHelpers

  setup_all_with_mocks([
    {Sanbase.Clickhouse.ApiCallData, [:passthrough],
     [active_users_count: fn _, _ -> {:ok, 10} end]}
  ]) do
    []
  end

  setup do
    user1 = insert(:user, inserted_at: Timex.shift(Timex.now(), days: -600))
    _user2 = insert(:user, inserted_at: Timex.shift(Timex.now(), days: -20))
    user3 = insert(:user, inserted_at: Timex.shift(Timex.now(), days: -2))
    user4 = insert(:staked_user, inserted_at: Timex.shift(Timex.now(), days: -500))
    _user5 = insert(:staked_user, inserted_at: Timex.shift(Timex.now(), days: -15))
    user6 = insert(:staked_user, inserted_at: Timex.shift(Timex.now(), days: -171))

    insert(:watchlist, %{user: user1})
    insert(:watchlist, %{user: user1})
    insert(:watchlist, %{user: user3})
    insert(:watchlist, %{user: user4})
    insert(:watchlist, %{user: user6})
    %{}
  end

  test "get user statistics" do
    statistics = Sanbase.Statistics.get_all()

    assert {"staking_users", %{"staking_users" => 3}} in statistics

    assert {"registered_users",
            %{
              "registered_users_last_180d" => 4,
              "registered_users_last_30d" => 3,
              "registered_users_last_7d" => 1,
              "registered_users_overall" => 6
            }} in statistics

    assert {"registered_staking_users",
            %{
              "registered_staking_users_last_180d" => 2,
              "registered_staking_users_last_30d" => 1,
              "registered_staking_users_last_7d" => 0,
              "registered_staking_users_overall" => 3
            }} in statistics
  end

  test "get tokens staked statistics" do
    statistics = Sanbase.Statistics.get_all()

    assert {"tokens_staked",
            %{
              "average_tokens_staked" => 2.0e4,
              "biggest_stake" => 2.0e4,
              "median_tokens_staked" => 2.0e4,
              "smallest_stake" => 2.0e4,
              "tokens_staked" => 6.0e4,
              "users_with_over_1000_san" => 3,
              "users_with_over_200_san" => 3
            }} in statistics
  end

  test "active users statistics" do
    statistics = Sanbase.Statistics.get_all()

    assert {"active_users",
            %{
              "active_users_in_last_12h" => 10,
              "active_users_in_last_24h" => 10,
              "active_users_in_last_7d" => 10,
              "active_users_in_last_30d" => 10
            }} in statistics
  end
end
