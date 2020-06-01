defmodule Sanbase.StatisticsTest do
  use Sanbase.DataCase

  import Sanbase.Auth.Settings, only: [daily_subscription_type: 0, weekly_subscription_type: 0]
  import Sanbase.Factory
  import Sanbase.TestHelpers

  import Mock

  setup_all_with_mocks([
    {Sanbase.Email.Mailchimp, [:passthrough], [unsubscribe_email: fn _ -> :ok end]},
    {Sanbase.Email.Mailchimp, [:passthrough], [subscribe_email: fn _ -> :ok end]}
  ]) do
    []
  end

  setup do
    user1 = insert(:user, inserted_at: Timex.shift(Timex.now(), days: -600))
    _user2 = insert(:user, inserted_at: Timex.shift(Timex.now(), days: -20))
    user3 = insert(:user, inserted_at: Timex.shift(Timex.now(), days: -2))
    user4 = insert(:staked_user, inserted_at: Timex.shift(Timex.now(), days: -500))
    user5 = insert(:staked_user, inserted_at: Timex.shift(Timex.now(), days: -15))
    user6 = insert(:staked_user, inserted_at: Timex.shift(Timex.now(), days: -171))

    Sanbase.Auth.UserSettings.change_newsletter_subscription(user1, %{
      newsletter_subscription: :weekly
    })

    Sanbase.Auth.UserSettings.change_newsletter_subscription(user3, %{
      newsletter_subscription: :weekly
    })

    Sanbase.Auth.UserSettings.change_newsletter_subscription(user5, %{
      newsletter_subscription: :daily
    })

    before_170d = Timex.shift(Timex.now(), days: -170)

    # Simulate that the user subscribed 170d ago, cannot be modified with changeset
    # as the `newsletter_subscription_updated_at` is not accepted as param but is
    # internally set.
    with_mock(DateTime, [:passthrough], utc_now: fn -> before_170d end) do
      Sanbase.Auth.UserSettings.change_newsletter_subscription(user6, %{
        newsletter_subscription: :weekly
      })
    end

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

  test "get newsletter statistics" do
    statistics = Sanbase.Statistics.get_all()

    assert {"users_with_weekly_newsletter_subscriptions",
            %{
              "subscribed_in_the_last_180_days" => 3,
              "subscribed_in_the_last_30_days" => 2,
              "subscribed_in_the_last_14_days" => 2,
              "subscribed_in_the_last_7_days" => 2,
              "subscribed_overall" => 3,
              "subscribed_new_users" => 1,
              "longtime_users_who_subscribed_in_the_last_14_days" => 1
            }} in statistics

    assert {"users_with_daily_newsletter_subscriptions",
            %{
              "subscribed_in_the_last_180_days" => 1,
              "subscribed_in_the_last_30_days" => 1,
              "subscribed_in_the_last_14_days" => 1,
              "subscribed_in_the_last_7_days" => 1,
              "subscribed_overall" => 1,
              "subscribed_new_users" => 0,
              "longtime_users_who_subscribed_in_the_last_14_days" => 1
            }} in statistics

    assert {"watchlists",
            %{
              "average_watchlists_per_user_with_watchlists" => 1.25,
              "users_with_watchlist_count" => 4,
              "watchlist_created_last_180d" => 5,
              "watchlist_created_last_30d" => 5,
              "watchlist_created_last_7d" => 5,
              "watchlist_created_overall" => 5,
              "new_users_with_watchlist_count_14d" => 1,
              "longtime_users_with_watchlist_count_14d" => 3
            }} in statistics
  end

  test "active users statistics" do
    rows = [3]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      statistics = Sanbase.Statistics.get_all()

      assert {"active_users",
              %{
                "active_users_in_last_12h" => 3,
                "active_users_in_last_24h" => 3,
                "active_users_in_last_7d" => 3,
                "active_users_in_last_30d" => 3
              }} in statistics
    end)
  end

  test "returns the number of users, which are subscribed" do
    assert Sanbase.Auth.Statistics.newsletter_subscribed_users_count(daily_subscription_type()) ==
             1

    assert Sanbase.Auth.Statistics.newsletter_subscribed_users_count(weekly_subscription_type()) ==
             3
  end

  test "returns the number of new users, which have a newsletter subscription" do
    now = Timex.now()

    assert Sanbase.Auth.Statistics.newsletter_subscribed_new_users_count(
             daily_subscription_type(),
             Timex.shift(now, days: -16)
           ) == 1

    assert Sanbase.Auth.Statistics.newsletter_subscribed_new_users_count(
             weekly_subscription_type(),
             Timex.shift(now, days: -14)
           ) == 1
  end

  test "returns the number of old users, which have subscribed for the newsletter in a given time period" do
    now = Timex.now()

    assert Sanbase.Auth.Statistics.newsletter_subscribed_old_users(
             daily_subscription_type(),
             Timex.shift(now, days: -5),
             Timex.shift(now, days: -14)
           ) == 1

    assert Sanbase.Auth.Statistics.newsletter_subscribed_old_users(
             weekly_subscription_type(),
             Timex.shift(now, days: -14),
             Timex.shift(now, days: -14)
           ) == 1

    assert Sanbase.Auth.Statistics.newsletter_subscribed_old_users(
             weekly_subscription_type(),
             Timex.shift(now, days: -9),
             Timex.shift(now, days: -25)
           ) == 1
  end
end
