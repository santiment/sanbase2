defmodule Sanbase.Auth.Statistics do
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Math
  alias Sanbase.Auth.{User, UserSettings}
  alias Sanbase.UserList

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

  @doc ~s"""
  Return the number of registered users, which use a given subscription type
  """
  def newsletter_subscribed_users_count(subscription_type) do
    user_settings_with_newsletter_subscription_query(subscription_type)
    |> count()
    |> Repo.one()
  end

  def newsletter_subscribed_users(subscription_type) do
    user_settings_with_newsletter_subscription_query(subscription_type)
    |> preload([:user])
    |> Repo.all()
    |> Enum.map(& &1.user)
  end

  @doc ~s"""
  Return the number of users registered after a given datetime, which use a given subscription type
  """
  def newsletter_subscribed_new_users_count(subscription_type, %DateTime{} = registered) do
    user_settings_with_newsletter_subscription_query(subscription_type)
    |> join(:inner, [u], us in assoc(u, :user))
    |> where([_us, u], u.inserted_at > ^registered)
    |> count()
    |> Repo.one()
  end

  @doc ~s"""
  Return the number of users registered before a given datetime, which have subscribed in the given time period
  """
  def newsletter_subscribed_old_users(
        subscription_type,
        %DateTime{} = registered_before,
        %DateTime{} = subscription_after
      ) do
    user_settings_with_newsletter_subscription_query(subscription_type)
    |> newsletter_updated_filter_query(
      subscription_after,
      Timex.now()
    )
    |> join(:inner, [u], us in assoc(u, :user))
    |> where([_us, u], u.inserted_at < ^registered_before)
    |> count()
    |> Repo.one()
  end

  @doc ~s"""
  Return the number of registered users, which use a given subscription type
  over a given course of time
  """
  def newsletter_subscribed_users_count(subscription_type, %DateTime{} = from, %DateTime{} = to) do
    user_settings_with_newsletter_subscription_query(subscription_type)
    |> newsletter_updated_filter_query(from, to)
    |> count()
    |> Repo.one()
  end

  # Resource could be watchlist, insight, user_trigger struct or any other struct which belongs to User
  # By passing queries: [list_of_queries] you can apply list of filters to the main query
  def resource_user_count_map(resource, opts \\ []) do
    queries = Keyword.get(opts, :queries, [])

    resource_query =
      from(
        r in resource,
        group_by: r.user_id,
        select: {r.user_id, count(r.user_id)}
      )

    query =
      Enum.reduce(queries, resource_query, fn query_func, acc ->
        query_func.(acc)
      end)

    query
    |> Repo.all()
    |> Enum.into(%{})
  end

  def user_screeners_count_map do
    resource_user_count_map(UserList,
      queries: [
        fn query ->
          from(r in query, where: fragment("?.function->>'name' != 'empty'", r))
        end
      ]
    )
  end

  def users_with_monitored_watchlist_and_email() do
    from(u in User,
      join: ul in UserList,
      on: ul.user_id == u.id,
      where: not is_nil(u.email) and ul.is_monitored == true,
      distinct: true
    )
    |> Repo.all()
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

  defp newsletter_updated_filter_query(base_query, %DateTime{} = from, %DateTime{} = to) do
    base_query
    |> where(
      fragment(
        """
        NOT settings->>'newsletter_subscription_updated_at_unix' IS NULL AND
        (settings->>'newsletter_subscription_updated_at_unix')::NUMERIC >= ? AND
        (settings->>'newsletter_subscription_updated_at_unix')::NUMERIC <= ?
        """,
        ^DateTime.to_unix(from),
        ^DateTime.to_unix(to)
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
