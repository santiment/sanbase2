# Build a CSV combining per-user API call counts (30/60/90 days) with their
# active Sanbase and SanAPI (business) subscriptions.
#
# - ClickHouse: count apikey calls per user for the last 30/60/90 days, split
#   into Sansheets calls (user_agent LIKE '%Google-Apps-Script%') and plain API
#   calls (everything else). Only users with >= 10 total apikey calls in the
#   last 90 days are kept.
# - Postgres: subscriptions that are currently active (status active/past_due)
#   or expired no more than 90 days ago (current_period_end within last 90
#   days), split into the Sanbase product (id 2) and the SanAPI/business
#   product (id 1) plan names.
#
# Output: api_call_subscription_analysis.csv in the current directory.
#
# Run with: mix run scripts/api_call_subscription_analysis.exs

defmodule ApiCallSubscriptionAnalysis do
  import Ecto.Query

  alias Sanbase.Accounts.User
  alias Sanbase.Billing.Product
  alias Sanbase.Billing.Subscription
  alias Sanbase.ClickhouseRepo
  alias Sanbase.Repo

  @output_file "api_call_subscription_analysis.csv"
  @min_calls_90d 10

  @header [
    "user_id",
    "email",
    "sanbase_sub",
    "sanapi_sub",
    "api_calls_30d",
    "api_calls_60d",
    "api_calls_90d",
    "sansheets_calls_30d",
    "sansheets_calls_60d",
    "sansheets_calls_90d"
  ]

  def run() do
    IO.puts("Fetching API call counts from ClickHouse...")
    api_calls = fetch_api_calls()
    user_ids = Enum.map(api_calls, & &1.user_id)
    IO.puts("Found #{length(user_ids)} users with >= #{@min_calls_90d} apikey calls in 90 days.")

    emails = fetch_emails(user_ids)
    subscriptions = fetch_subscriptions(user_ids)

    rows =
      Enum.map(api_calls, fn %{user_id: user_id} = row ->
        subs = Map.get(subscriptions, user_id, %{})

        [
          user_id,
          Map.get(emails, user_id, ""),
          Map.get(subs, Product.product_sanbase(), ""),
          Map.get(subs, Product.product_api(), ""),
          row.api_30d,
          row.api_60d,
          row.api_90d,
          row.sansheets_30d,
          row.sansheets_60d,
          row.sansheets_90d
        ]
      end)

    iodata = NimbleCSV.RFC4180.dump_to_iodata([@header | rows])
    File.write!(@output_file, iodata)

    IO.puts("Wrote #{length(rows)} rows to #{Path.expand(@output_file)}")
  end

  defp fetch_api_calls() do
    now = DateTime.utc_now()
    d30 = DateTime.add(now, -30, :day)
    d60 = DateTime.add(now, -60, :day)
    d90 = DateTime.add(now, -90, :day)

    sql = """
    SELECT
      user_id,
      toUInt64(countIf(dt >= toDateTime({{d30}}) AND user_agent NOT LIKE '%Google-Apps-Script%')) AS api_30d,
      toUInt64(countIf(dt >= toDateTime({{d60}}) AND user_agent NOT LIKE '%Google-Apps-Script%')) AS api_60d,
      toUInt64(countIf(user_agent NOT LIKE '%Google-Apps-Script%')) AS api_90d,
      toUInt64(countIf(dt >= toDateTime({{d30}}) AND user_agent LIKE '%Google-Apps-Script%')) AS sansheets_30d,
      toUInt64(countIf(dt >= toDateTime({{d60}}) AND user_agent LIKE '%Google-Apps-Script%')) AS sansheets_60d,
      toUInt64(countIf(user_agent LIKE '%Google-Apps-Script%')) AS sansheets_90d
    FROM api_call_data
    WHERE
      dt >= toDateTime({{d90}}) AND
      auth_method = 'apikey' AND
      user_id != 0
    GROUP BY user_id
    HAVING (api_90d + sansheets_90d) >= {{min_calls_90d}}
    ORDER BY api_90d DESC
    """

    params = %{d30: d30, d60: d60, d90: d90, min_calls_90d: @min_calls_90d}
    query_struct = Sanbase.Clickhouse.Query.new(sql, params)

    {:ok, result} =
      ClickhouseRepo.query_transform(query_struct, fn [user_id, api30, api60, api90, sans30, sans60, sans90] ->
        %{
          user_id: user_id,
          api_30d: api30,
          api_60d: api60,
          api_90d: api90,
          sansheets_30d: sans30,
          sansheets_60d: sans60,
          sansheets_90d: sans90
        }
      end)

    result
  end

  defp fetch_emails(user_ids) do
    from(u in User, where: u.id in ^user_ids, select: {u.id, u.email})
    |> Repo.all()
    |> Map.new()
  end

  # Returns %{user_id => %{product_id => plan_label}} for subscriptions that are
  # currently active or expired no more than 90 days ago. A subscription is
  # treated as active when its status is active/past_due or when its current
  # period has not ended yet (e.g. a canceled-at-period-end or trialing sub that
  # still grants access); otherwise it is labeled "(expired)". Ordered by
  # current_period_end ascending so the latest-ending subscription wins per
  # product.
  defp fetch_subscriptions(user_ids) do
    now = DateTime.utc_now()
    cutoff = DateTime.add(now, -90, :day)

    from(s in Subscription,
      join: p in assoc(s, :plan),
      join: pr in assoc(p, :product),
      where: s.user_id in ^user_ids,
      where: s.status in [:active, :past_due] or s.current_period_end >= ^cutoff,
      order_by: [asc: s.current_period_end],
      select: {s.user_id, pr.id, p.name, s.status, s.current_period_end}
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn {user_id, product_id, plan_name, status, current_period_end}, acc ->
      active? =
        status in [:active, :past_due] or
          (not is_nil(current_period_end) and DateTime.compare(current_period_end, now) != :lt)

      label = plan_name <> if(active?, do: " (active)", else: " (expired)")

      Map.update(acc, user_id, %{product_id => label}, fn map ->
        Map.put(map, product_id, label)
      end)
    end)
  end
end

ApiCallSubscriptionAnalysis.run()
