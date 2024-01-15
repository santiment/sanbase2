defmodule Sanbase.Statistics do
  alias Sanbase.Clickhouse.ApiCallData
  alias Sanbase.Accounts.Statistics, as: UserStatistics
  alias Sanbase.UserLists.Statistics, as: WatchlistStatistics

  @statistics [
    "staking_users",
    "registered_users",
    "registered_staking_users",
    "watchlists",
    "tokens_staked",
    "active_users"
  ]

  @epoch_datetime 0 |> DateTime.from_unix!()

  def available_stats() do
    @statistics
  end

  @doc ~s"""
  Returns a map with statistics for sanbase.
  Each key is the name of the statistic and value is its value
  """
  def get_all() do
    Enum.map(@statistics, fn stat -> {stat, get(stat)} end)
  end

  def get("registered_users") do
    now = Timex.now()
    last_7d = UserStatistics.registered_users(Timex.shift(now, days: -7), now)
    last_30d = UserStatistics.registered_users(Timex.shift(now, days: -30), now)
    last_180d = UserStatistics.registered_users(Timex.shift(now, days: -180), now)
    overall = UserStatistics.registered_users(@epoch_datetime, now)

    %{
      "registered_users_last_7d" => last_7d,
      "registered_users_last_30d" => last_30d,
      "registered_users_last_180d" => last_180d,
      "registered_users_overall" => overall
    }
  end

  def get("registered_staking_users") do
    now = Timex.now()
    last_7d = UserStatistics.registered_staking_users(Timex.shift(now, days: -7), now)
    last_30d = UserStatistics.registered_staking_users(Timex.shift(now, days: -30), now)
    last_180d = UserStatistics.registered_staking_users(Timex.shift(now, days: -180), now)
    overall = UserStatistics.registered_staking_users(@epoch_datetime, now)

    %{
      "registered_staking_users_last_7d" => last_7d,
      "registered_staking_users_last_30d" => last_30d,
      "registered_staking_users_last_180d" => last_180d,
      "registered_staking_users_overall" => overall
    }
  end

  def get("staking_users") do
    %{
      "staking_users" => UserStatistics.staking_users()
    }
  end

  def get("tokens_staked") do
    # Returns a map of total, average and median tokens staked
    UserStatistics.tokens_staked()
  end

  def get("watchlists") do
    now = Timex.now()
    last_7d = WatchlistStatistics.watchlists_created(Timex.shift(now, days: -7), now)
    last_30d = WatchlistStatistics.watchlists_created(Timex.shift(now, days: -30), now)
    last_180d = WatchlistStatistics.watchlists_created(Timex.shift(now, days: -180), now)
    overall = WatchlistStatistics.watchlists_created(@epoch_datetime, now)

    users_with_watchlist_count = WatchlistStatistics.users_with_watchlist_count()

    new_users_with_watchlist_count_14d =
      WatchlistStatistics.new_users_with_watchlist_count(Timex.shift(now, days: -14))

    old_users_with_watchlist_count_14d =
      WatchlistStatistics.old_users_with_new_watchlist_count(
        Timex.shift(now, days: -14),
        Timex.shift(now, days: -14)
      )

    average_watchlists_per_user =
      if users_with_watchlist_count > 0 do
        overall / users_with_watchlist_count
      else
        +0.0
      end
      |> Float.round(2)

    %{
      "watchlist_created_last_7d" => last_7d,
      "watchlist_created_last_30d" => last_30d,
      "watchlist_created_last_180d" => last_180d,
      "watchlist_created_overall" => overall,
      "users_with_watchlist_count" => users_with_watchlist_count,
      "average_watchlists_per_user_with_watchlists" => average_watchlists_per_user,
      "new_users_with_watchlist_count_14d" => new_users_with_watchlist_count_14d,
      "longtime_users_with_watchlist_count_14d" => old_users_with_watchlist_count_14d
    }
  end

  def get("active_users") do
    now = Timex.now()

    {:ok, active_users_in_last_12h} =
      ApiCallData.active_users_count(Timex.shift(now, hours: -12), now)

    {:ok, active_users_in_last_24h} =
      ApiCallData.active_users_count(Timex.shift(now, days: -1), now)

    {:ok, active_users_in_last_7d} =
      ApiCallData.active_users_count(Timex.shift(now, days: -7), now)

    {:ok, active_users_in_last_30d} =
      ApiCallData.active_users_count(Timex.shift(now, days: -30), now)

    %{
      "active_users_in_last_12h" => active_users_in_last_12h,
      "active_users_in_last_24h" => active_users_in_last_24h,
      "active_users_in_last_7d" => active_users_in_last_7d,
      "active_users_in_last_30d" => active_users_in_last_30d
    }
  end
end
