defmodule Sanbase.Accounts.Statistics do
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Math
  alias Sanbase.Accounts.{Role, UserRole, User}
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

  @spec santiment_team_users() :: list(%User{})
  def santiment_team_users() do
    santiment_role_user_ids = Sanbase.Accounts.Role.san_team_ids()

    # Get all users whose email ends with @santiment.net or they have the santiment role.
    # There are cases where santiment members use accounts with other email domains
    from(u in User,
      where:
        (like(u.email, "%@santiment.net") or u.id in ^santiment_role_user_ids) and
          u.is_registered == true
    )
    |> Repo.all()
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
