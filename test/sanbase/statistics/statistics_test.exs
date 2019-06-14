defmodule Sanbase.StatisticsTest do
  use Sanbase.DataCase

  import Sanbase.Factory
  import Mock

  setup do
    u1 = insert(:user)

    Ecto.Changeset.change(u1, %{inserted_at: Timex.shift(Timex.now(), days: -600)})
    |> Sanbase.Repo.update()

    Sanbase.Auth.UserSettings.change_newsletter_subscription(u1, %{
      newsletter_subscription: :weekly
    })

    u2 = insert(:user)

    Ecto.Changeset.change(u2, %{inserted_at: Timex.shift(Timex.now(), days: -20)})
    |> Sanbase.Repo.update()

    u3 = insert(:user)

    Ecto.Changeset.change(u3, %{inserted_at: Timex.shift(Timex.now(), days: -2)})
    |> Sanbase.Repo.update()

    Sanbase.Auth.UserSettings.change_newsletter_subscription(u3, %{
      newsletter_subscription: :weekly
    })

    u4 = insert(:staked_user)

    Ecto.Changeset.change(u4, %{inserted_at: Timex.shift(Timex.now(), days: -500)})
    |> Sanbase.Repo.update()

    u5 = insert(:staked_user)

    Ecto.Changeset.change(u5, %{inserted_at: Timex.shift(Timex.now(), days: -15)})
    |> Sanbase.Repo.update()

    Sanbase.Auth.UserSettings.change_newsletter_subscription(u5, %{
      newsletter_subscription: :daily
    })

    u6 = insert(:staked_user)

    Ecto.Changeset.change(u6, %{inserted_at: Timex.shift(Timex.now(), days: -1)})
    |> Sanbase.Repo.update()

    before_170d = Timex.shift(Timex.now(), days: -170)

    # Simulate that the user subscribed 170d ago, cannot be modified with changeset
    # as the `newsletter_subscription_updated_at` is not accepted as param but is
    # internally set.
    with_mock(DateTime, [:passthrough], utc_now: fn -> before_170d end) do
      Sanbase.Auth.UserSettings.change_newsletter_subscription(u6, %{
        newsletter_subscription: :weekly
      })
    end

    insert(:watchlist, %{user: u1})
    insert(:watchlist, %{user: u1})
    insert(:watchlist, %{user: u3})
    insert(:watchlist, %{user: u4})
    insert(:watchlist, %{user: u6})
    %{}
  end

  test "get user statistics" do
    statistics = Sanbase.Statistics.get_all()

    assert {"staking_users", %{"staking_users" => 3}} in statistics

    assert {"registered_users",
            %{
              "registered_users_last_180d" => 4,
              "registered_users_last_30d" => 4,
              "registered_users_last_7d" => 2,
              "registered_users_overall" => 6
            }} in statistics

    assert {"registered_staking_users",
            %{
              "registered_staking_users_last_180d" => 2,
              "registered_staking_users_last_30d" => 2,
              "registered_staking_users_last_7d" => 1,
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

    assert {"weekly_newsletter_subscriptions",
            %{
              "weekly_updates_subscribed_user_count_last_180d" => 3,
              "weekly_updates_subscribed_user_count_last_30d" => 2,
              "weekly_updates_subscribed_user_count_last_7d" => 2,
              "weekly_updates_subscribed_user_count_overall" => 3
            }} in statistics

    assert {"daily_newsletter_subscriptions",
            %{
              "daily_updates_subscribed_user_count_last_180d" => 1,
              "daily_updates_subscribed_user_count_last_30d" => 1,
              "daily_updates_subscribed_user_count_last_7d" => 1,
              "daily_updates_subscribed_user_count_overall" => 1
            }} in statistics

    assert {"watchlists",
            %{
              "average_watchlists_per_user_with_watchlists" => 1.25,
              "users_with_watchlist_count" => 4,
              "watchlist_created_last_180d" => 5,
              "watchlist_created_last_30d" => 5,
              "watchlist_created_last_7d" => 5,
              "watchlist_created_overall" => 5
            }} in statistics
  end
end
