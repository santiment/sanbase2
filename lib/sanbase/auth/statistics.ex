defmodule Sanbase.Auth.Statistics do
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Math
  alias Sanbase.Auth.{User, Settings, UserSettings}

  def tokens_staked() do
    san_balances =
      from(u in User)
      |> positive_san_balance()
      |> select([u], u.san_balance)
      |> Repo.all()
      |> Enum.map(&Decimal.to_float/1)

    {min_stake, max_stake} = Sanbase.Math.min_max(san_balances)

    %{
      "average_tokens_staked" => Math.average(san_balances),
      "median_tokens_staked" => Math.median(san_balances),
      "tokens_staked" => Enum.sum(san_balances) |> Kernel.*(1.0) |> Float.round(2),
      "biggest_stake" => max_stake |> Kernel.*(1.0) |> Float.round(2),
      "smallest_stake" => min_stake |> Kernel.*(1.0) |> Float.round(2),
      "users_with_over_1000_san" => Enum.count(san_balances, fn balance -> balance >= 1000 end),
      "users_with_over_200_san" => Enum.count(san_balances, fn balance -> balance >= 200 end)
    }
  end

  @doc ~s"""
  Return the number of all users that are staking tokens
  """
  @spec staking_users() :: non_neg_integer()
  def staking_users() do
    from(u in User)
    |> positive_san_balance()
    |> count()
    |> Repo.one()
  end

  @doc ~s"""
  Return the number of newly registered users in the given time interval
  """
  @spec registered_users(DateTime.t(), DateTime.t()) :: non_neg_integer()
  def registered_users(%DateTime{} = from, %DateTime{} = to) do
    registered_users_query(from, to)
    |> count()
    |> Repo.one()
  end

  @doc ~s"""
  Return the number of newly registered users in the given time interval that have
  positive SAN balance
  """
  @spec registered_staking_users(DateTime.t(), DateTime.t()) :: non_neg_integer()
  def registered_staking_users(%DateTime{} = from, %DateTime{} = to) do
    registered_users_query(from, to)
    |> positive_san_balance()
    |> count()
    |> Repo.one()
  end

  def weekly_updates_subscribed_user_count() do
    user_settings_with_newsletter_subscription_query(Settings.weekly_subscription_type())
    |> count()
    |> Repo.one()
  end

  def daily_updates_subscribed_user_count() do
    user_settings_with_newsletter_subscription_query(Settings.daily_subscription_type())
    |> count()
    |> Repo.one()
  end

  # Private functions

  defp user_settings_with_newsletter_subscription_query(subscription_type) do
    from(us in UserSettings,
      where:
        fragment(
          """
          settings->>'newsletter_subscription' = ?
          """,
          ^subscription_type
        )
    )
  end

  defp registered_users_query(from, to) do
    from_naive = DateTime.to_naive(from)
    to_naive = DateTime.to_naive(to)

    from(
      u in User,
      where: u.inserted_at >= ^from_naive and u.inserted_at <= ^to_naive
    )
  end

  defp positive_san_balance(query) do
    from(
      u in query,
      where: not is_nil(u.san_balance) and u.san_balance > 0
    )
  end

  defp count(query) do
    query
    |> select(fragment("count(*)"))
  end
end
