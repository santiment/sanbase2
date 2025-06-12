defmodule Sanbase.Mix.LogoutExcessiveUsage do
  def run() do
    {:ok, user_ids} = get_offenders()
    # Do some whitelisting
    user_ids == user_ids -- whitelist_user_ids()
    user_ids = Enum.map(user_ids, &to_string/1)

    case SanbaseWeb.Guardian.Token.revoke_all_with_user_id(user_ids) do
      {:ok, _} ->
        IO.puts("""
        Revoked all tokens for users with excessive usage: #{inspect(user_ids)}
        This usage pattern indicates people using Sanbase access pattern in scripts
        or scraping, which is not allowed.
        """)

      {:error, reason} ->
        IO.puts("""
        Failed to revoke tokens for users with excessive usage: #{inspect(user_ids)}.
        Reason: #{inspect(reason)}
        """)
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

      -- users who made unrealistically many sanbase calls in a month, most likely scraping
      SELECT user_id
      FROM
      (
          SELECT
              user_id,
              toMonth(dt) AS month,
              count(*) AS cnt
          FROM api_call_data
          WHERE (dt >= (now() - toIntervalDay(60))) AND (auth_method = 'jwt') AND (query LIKE 'getMetric%')
          GROUP BY
              user_id,
              month
          ORDER BY cnt DESC
          LIMIT 1 BY user_id
          LIMIT 50
      )
      WHERE cnt > 150_000

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
end
