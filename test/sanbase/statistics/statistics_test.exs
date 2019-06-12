defmodule Sanbase.StatisticsTest do
  use Sanbase.DataCase

  import Sanbase.Factory

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

    Sanbase.Auth.UserSettings.change_newsletter_subscription(u6, %{
      newsletter_subscription: :weekly
    })

    insert(:watchlist, %{user: u1})
    insert(:watchlist, %{user: u1})
    insert(:watchlist, %{user: u3})
    insert(:watchlist, %{user: u4})
    insert(:watchlist, %{user: u6})
    %{}
  end

  test "get all statistics" do
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

    assert {"weekly_updates_subscribed_user_count",
            %{"weekly_updates_subscribed_user_count" => 3}} in statistics

    assert {"daily_updates_subscribed_user_count",
            %{
              "daily_updates_subscribed_user_count" => 1
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
end
