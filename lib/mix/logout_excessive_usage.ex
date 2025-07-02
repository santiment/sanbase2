defmodule Sanbase.Mix.LogoutExcessiveUsage do
  require Logger

  def run() do
    if enabled?() do
      {:ok, user_ids} = get_offenders()
      # Do some whitelisting
      user_ids = user_ids -- whitelist_user_ids()
      user_ids = Enum.map(user_ids, &to_string/1)

      {user_ids_with_subscription, user_ids_without_subscription} =
        split_user_ids_by_subscription(user_ids)

      # Be more aggresiive against non-paying users. Users with Sanbase PRO
      # will be affected much less often (once every 8 hours)
      user_ids_to_logout =
        if time_to_logout_all?(),
          do: user_ids_with_subscription ++ user_ids_without_subscription,
          else: user_ids_without_subscription

      case SanbaseWeb.Guardian.Token.revoke_all_with_user_id(user_ids_to_logout) do
        {:ok, _} ->
          Logger.info("""
          Revoked all tokens for users with excessive usage: #{inspect(user_ids_to_logout)}
          This usage pattern indicates people using Sanbase access pattern in scripts
          or scraping, which is not allowed.
          """)

        {:error, reason} ->
          Logger.info("""
          Failed to revoke tokens for users with excessive usage: #{inspect(user_ids_to_logout)}.
          Reason: #{inspect(reason)}
          """)
      end
    else
      Logger.info("""
      Scheduled running #{__MODULE__} but won't run as it's not enabled via env var
      """)
    end
  end

  def time_to_logout_all?() do
    now = DateTime.utc_now()
    rem(now.hour, 8) == 0
  end

  def enabled?() do
    case System.get_env("SANBASE_LOGOUT_EXCESSIVE_USAGE") do
      x when x in ["True", "true", "1"] -> true
      _ -> false
    end
  end

  def get_offenders() do
    sql = """
    SELECT DISTINCT(user_id) FROM
    (
      -- users who made unrealistically many sanbase calls in a day, most likely scraping
      SELECT user_id
      FROM
      (
          SELECT
              user_id,
              toDate(dt) AS day,
              count(*) AS cnt
          FROM api_call_data
          WHERE (dt >= (now() - toIntervalDay(3))) AND (auth_method = 'jwt') AND (query LIKE 'getMetric%')
          GROUP BY
              user_id,
              day
          ORDER BY cnt DESC
          LIMIT 1 BY user_id
          LIMIT 50
      )
      WHERE cnt > 15_000

      UNION ALL

      -- users who simply forgot to hide they're making calls from python
      SELECT user_id
      FROM
      (
          SELECT
              user_id,
              count(*) AS cnt
          FROM api_call_data
          WHERE (dt >= (now() - toIntervalDay(3))) AND (auth_method = 'jwt') AND (user_agent LIKE '%python-requests%')
          GROUP BY user_id
          ORDER BY cnt DESC
          LIMIT 1 BY user_id
          LIMIT 50
      )
      WHERE cnt > 100

      UNION ALL

      -- users who don't sleep, most likely bots
      WITH 3 AS days
      SELECT user_id
      FROM
      (
          SELECT
              user_id,
              count(distinct(toStartOfHour(dt))) AS hours_active
          FROM api_call_data
          WHERE (dt >= (now() - toIntervalDay(days))) AND (auth_method = 'jwt')
          GROUP BY
              user_id
          ORDER BY hours_active DESC
          LIMIT 100
      )
      WHERE hours_active > 18*days
    )
    """

    query_struct = Sanbase.Clickhouse.Query.new(sql, %{})

    Sanbase.ClickhouseRepo.query_transform(query_struct, fn [user_id] -> user_id end)
  end

  def whitelist_user_ids() do
    user_ids_str = System.get_env("WHITELIST_USER_IDS_DO_NOT_LOGOUT") || ""

    String.split(user_ids_str, ",", trim: true) |> Enum.map(&String.to_integer/1)
  end

  defp split_user_ids_by_subscription(user_ids) do
    {_with_subscription, _without_subscription} =
      Enum.split_with(user_ids, fn user_id ->
        Sanbase.Billing.Subscription.user_has_active_sanbase_subscriptions?(user_id)
      end)
  end
end
