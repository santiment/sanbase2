defmodule Sanbase.Accounts.UserStats do
  @moduledoc """
  Stats module for analyzing user activity patterns and identifying inactive users
  """

  import Ecto.Query
  alias Sanbase.Repo
  alias Sanbase.Accounts.User
  alias Sanbase.Billing.{Subscription, Product}
  alias Sanbase.Clickhouse.ApiCallData

  @spec inactive_free_users_count() ::
          {:ok, %{count: non_neg_integer(), emails: list(String.t())}} | {:error, String.t()}
  def inactive_free_users_count do
    one_month_ago = DateTime.utc_now() |> DateTime.add(-30, :day)
    two_months_ago = DateTime.utc_now() |> DateTime.add(-60, :day)

    with {:ok, free_users} <- get_free_users(),
         {:ok, recently_active_users} <- get_recently_active_users(one_month_ago),
         {:ok, previously_active_users} <-
           get_previously_active_users(two_months_ago, one_month_ago) do
      inactive_user_ids =
        free_users
        |> MapSet.new()
        |> MapSet.difference(MapSet.new(recently_active_users))
        |> MapSet.intersection(MapSet.new(previously_active_users))
        |> MapSet.to_list()

      emails = get_user_emails(inactive_user_ids)

      {:ok, %{count: length(emails), emails: emails}}
    end
  end

  @doc """
  Get count of users whose trial ended and are inactive for 2 weeks.
  """
  @spec trial_ended_inactive_users_count() ::
          {:ok, %{count: non_neg_integer(), emails: list(String.t())}} | {:error, String.t()}
  def trial_ended_inactive_users_count do
    one_month_ago = DateTime.utc_now() |> DateTime.add(-30, :day)
    two_weeks_ago = DateTime.utc_now() |> DateTime.add(-14, :day)

    with {:ok, trial_ended_users} <- get_trial_ended_users(one_month_ago, two_weeks_ago),
         {:ok, recently_active_users} <- get_api_active_users_since(two_weeks_ago) do
      inactive_user_ids =
        trial_ended_users
        |> MapSet.new()
        |> MapSet.difference(MapSet.new(recently_active_users))
        |> MapSet.to_list()

      emails = get_user_emails(inactive_user_ids)

      {:ok, %{count: length(emails), emails: emails}}
    end
  end

  @doc """
  Get count of API customers who have cancelled their subscriptions.
  """
  @spec cancelled_api_customers_count() ::
          {:ok, %{count: non_neg_integer(), emails: list(String.t())}} | {:error, String.t()}
  def cancelled_api_customers_count do
    one_month_ago = DateTime.utc_now() |> DateTime.add(-30, :day)

    users_with_cancelled_subscriptions =
      from(s in Subscription,
        join: p in assoc(s, :plan),
        where:
          p.product_id == ^Product.product_api() and s.status == :canceled and
            s.updated_at > ^one_month_ago,
        select: s.user_id,
        distinct: s.user_id
      )
      |> Repo.all()

    users_with_active_subscriptions =
      from(s in Subscription,
        left_join: p in assoc(s, :plan),
        where:
          p.product_id == ^Product.product_api() and s.status == :active and
            s.user_id in ^users_with_cancelled_subscriptions,
        select: s.user_id,
        distinct: s.user_id
      )
      |> Repo.all()

    cancelled_user_ids = users_with_cancelled_subscriptions -- users_with_active_subscriptions
    emails = get_user_emails(cancelled_user_ids)

    {:ok, %{count: length(emails), emails: emails}}
  end

  @doc """
  Get count of API customers who stopped calling API for few weeks but have active subscriptions.
  """
  @spec inactive_active_api_customers_count() ::
          {:ok, %{count: non_neg_integer(), emails: list(String.t())}} | {:error, String.t()}
  def inactive_active_api_customers_count do
    three_weeks_ago = DateTime.utc_now() |> DateTime.add(-21, :day)

    with {:ok, active_api_customers} <- get_active_api_customers(),
         {:ok, recently_active_users} <- get_api_active_users_since(three_weeks_ago) do
      inactive_user_ids =
        active_api_customers
        |> MapSet.new()
        |> MapSet.difference(MapSet.new(recently_active_users))
        |> MapSet.to_list()

      emails = get_user_emails(inactive_user_ids)

      {:ok, %{count: length(emails), emails: emails}}
    end
  end

  @doc """
  Get all stats together for efficient caching.
  """
  @spec get_all_stats() :: {:ok, map()} | {:error, String.t()}
  def get_all_stats do
    with {:ok, inactive_free} <- inactive_free_users_count(),
         {:ok, trial_ended_inactive} <- trial_ended_inactive_users_count(),
         {:ok, cancelled_api} <- cancelled_api_customers_count(),
         {:ok, inactive_active_api} <- inactive_active_api_customers_count() do
      stats = %{
        inactive_free_users_count: inactive_free.count,
        trial_ended_inactive_users_count: trial_ended_inactive.count,
        cancelled_api_customers_count: cancelled_api.count,
        inactive_active_api_customers_count: inactive_active_api.count,
        # inactive_free_users_emails: inactive_free.emails,
        # trial_ended_inactive_users_emails: trial_ended_inactive.emails,
        # cancelled_api_customers_emails: cancelled_api.emails,
        # inactive_active_api_customers_emails: inactive_active_api.emails,
        calculated_at: DateTime.utc_now()
      }

      {:ok, stats}
    end
  end

  # Private functions

  defp get_free_users do
    # Users are considered "free" if they don't have any active paid subscriptions
    paid_user_ids =
      from(s in Subscription,
        join: p in assoc(s, :plan),
        where: s.status in [:active, :trialing, :past_due] and p.amount > 0,
        select: s.user_id,
        distinct: s.user_id
      )
      |> Repo.all()

    all_user_ids =
      from(u in User,
        select: u.id
      )
      |> Repo.all()

    free_users = all_user_ids -- paid_user_ids
    {:ok, free_users}
  end

  defp get_recently_active_users(since_datetime) do
    query_struct = active_users_since_query(since_datetime)

    case Sanbase.ClickhouseRepo.query_transform(query_struct, fn [user_id] -> user_id end) do
      {:ok, user_ids} -> {:ok, user_ids}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_previously_active_users(from_datetime, to_datetime) do
    query_struct = active_users_between_query(from_datetime, to_datetime)

    case Sanbase.ClickhouseRepo.query_transform(query_struct, fn [user_id] -> user_id end) do
      {:ok, user_ids} -> {:ok, user_ids}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_ever_active_users do
    query_struct = ever_active_users_query()

    case Sanbase.ClickhouseRepo.query_transform(query_struct, fn [user_id] -> user_id end) do
      {:ok, user_ids} -> {:ok, user_ids}
      {:error, reason} -> {:error, reason}
    end
  end

  defp active_users_since_query(since_datetime) do
    sql = """
    SELECT DISTINCT user_id
    FROM api_call_data
    WHERE dt >= toDateTime({{since_datetime}}) AND user_id != 0
    """

    params = %{since_datetime: since_datetime}
    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp active_users_between_query(from_datetime, to_datetime) do
    sql = """
    SELECT DISTINCT user_id
    FROM api_call_data
    WHERE dt >= toDateTime({{from_datetime}})
      AND dt < toDateTime({{to_datetime}})
      AND user_id != 0
    """

    params = %{from_datetime: from_datetime, to_datetime: to_datetime}
    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp ever_active_users_query do
    sql = """
    SELECT DISTINCT user_id
    FROM api_call_data
    WHERE user_id != 0
    """

    params = %{}
    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp get_trial_ended_users(from_datetime, to_datetime) do
    # Users whose trial ended before the given date and don't have active subscriptions
    query =
      from(s in Subscription,
        where:
          s.status == :canceled and
            not is_nil(s.trial_end) and
            s.trial_end >= ^from_datetime and
            s.trial_end < ^to_datetime,
        select: s.user_id,
        distinct: s.user_id
      )

    trial_ended_users = Repo.all(query)
    {:ok, trial_ended_users}
  end

  defp get_api_active_users_since(since_datetime) do
    query_struct = api_active_users_since_query(since_datetime)

    case Sanbase.ClickhouseRepo.query_transform(query_struct, fn [user_id] -> user_id end) do
      {:ok, user_ids} -> {:ok, user_ids}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_active_api_customers do
    # Users with active API subscriptions
    query =
      from(s in Subscription,
        join: p in assoc(s, :plan),
        where:
          p.product_id == ^Product.product_api() and
            s.status in [:active, :trialing, :past_due],
        select: s.user_id,
        distinct: s.user_id
      )

    active_customers = Repo.all(query)
    {:ok, active_customers}
  end

  defp api_active_users_since_query(since_datetime) do
    sql = """
    SELECT DISTINCT user_id
    FROM api_call_data
    WHERE dt >= toDateTime({{since_datetime}})
      AND user_id != 0
      AND auth_method = 'apikey'
    """

    params = %{since_datetime: since_datetime}
    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp get_user_emails(user_ids) when is_list(user_ids) do
    from(u in User,
      where: u.id in ^user_ids and not like(u.email, "%@santiment.net"),
      select: u.email
    )
    |> Repo.all()
    |> Enum.filter(& &1)
  end
end
