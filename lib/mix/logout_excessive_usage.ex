defmodule Sanbase.Mix.LogoutExcessiveUsage do
  def run() do
    {:ok, user_ids} = get_offenders()
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

      SELECT user_id
      FROM
      (
          SELECT
              user_id,
              toMonth(dt) AS month,
              count(*) AS cnt
          FROM api_call_data
          WHERE (dt >= (now() - toIntervalDay(14))) AND (auth_method = 'jwt') AND (query LIKE 'getMetric%')
          GROUP BY
              user_id,
              month
          ORDER BY cnt DESC
          LIMIT 1 BY user_id
          LIMIT 50
      )
      WHERE cnt > 150_000
    )
    """

    query_struct = Sanbase.Clickhouse.Query.new(sql, %{})

    Sanbase.ClickhouseRepo.query_transform(query_struct, fn [user_id] -> user_id end)
  end
end
