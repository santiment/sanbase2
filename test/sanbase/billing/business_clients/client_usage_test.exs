defmodule Sanbase.Billing.BusinessClients.ClientUsageTest do
  use Sanbase.DataCase, async: false

  @moduletag capture_log: true

  import Sanbase.Factory

  alias Sanbase.Billing.BusinessClients.ClientUsage

  @today ~D[2026-11-25]

  defp with_clickhouse(fun, responder) do
    Sanbase.Mock.prepare_mock(Sanbase.ClickhouseRepo, :query, fn sql, args, _opts ->
      responder.(sql, args)
    end)
    |> Sanbase.Mock.run_with_mocks(fun)
  end

  describe "windows/1" do
    test "two windows of 30 whole days, today left out" do
      assert ClientUsage.windows(@today) == %{
               from: ~U[2026-09-26 00:00:00Z],
               middle: ~U[2026-10-26 00:00:00Z],
               until: ~U[2026-11-25 00:00:00Z]
             }
    end
  end

  describe "api/2" do
    test "totals, queries, assets and connections from one client's API key calls" do
      test_pid = self()

      result =
        with_clickhouse(fn -> ClientUsage.api(7, @today) end, fn sql, args ->
          send(test_pid, {:args, args})

          cond do
            sql =~ "ARRAY JOIN" ->
              {:ok, %{rows: [["bitcoin", 900, 1_000], ["ethereum", 0, 400]]}}

            sql =~ "user_agent" ->
              {:ok,
               %{
                 rows: [
                   ["python-requests/2.32.3", 600],
                   ["Python/3.12 aiohttp/3.9", 200],
                   ["Mozilla/5.0 (compatible; Google-Apps-Script)", 200]
                 ]
               }}

            true ->
              {:ok,
               %{
                 rows: [
                   ["getMetric|mvrv_usd", 1_000, 1_200, 30],
                   ["getMetric|exchange_inflow", 0, 800, 0]
                 ]
               }}
          end
        end)

      assert {:ok, api} = result
      assert api.calls == %{current: 1_000, previous: 2_000}
      assert api.errors == 30

      assert [%{name: "getMetric|mvrv_usd", current: 1_000, previous: 1_200, errors: 30} | _] =
               api.queries

      assert api.assets == [
               %{slug: "bitcoin", current: 900, previous: 1_000},
               %{slug: "ethereum", current: 0, previous: 400}
             ]

      assert [%{label: "Python", calls: 800}, %{label: "Google Sheets", calls: 200}] =
               api.connections

      # The client and the bounds are parameters, not interpolated.
      assert_received {:args, %{"user_id" => 7, "middle" => ~U[2026-10-26 00:00:00Z]}}
    end

    test "a failed query is an error" do
      result =
        with_clickhouse(fn -> ClientUsage.api(7, @today) end, fn _sql, _args ->
          {:error, "timeout"}
        end)

      assert result == :error
    end
  end

  describe "web/2" do
    test "page views per area of the app and SQL runs" do
      result =
        with_clickhouse(fn -> ClientUsage.web(7, @today) end, fn sql, _args ->
          if sql =~ "sanbase_user_events" do
            {:ok,
             %{
               rows: [
                 ["charts", 40, 10],
                 ["__charts", 2, 0],
                 ["pricing", 3, 0],
                 ["", 5, 5],
                 ["something-new", 1, 0]
               ]
             }}
          else
            {:ok, %{rows: [[12, 4]]}}
          end
        end)

      assert {:ok, web} = result

      assert web.areas == [
               %{area: "Charts", current: 42, previous: 10},
               %{area: "Home", current: 5, previous: 5},
               %{area: "Pricing page", current: 3, previous: 0},
               %{area: "Other", current: 1, previous: 0}
             ]

      assert web.sql_runs == %{current: 12, previous: 4}
    end
  end

  describe "creations/2" do
    test "counts what the client built, deleted items left out" do
      user = insert(:user)
      other = insert(:user)

      insert(:watchlist, user: user)
      insert(:watchlist, user: user, is_deleted: true)
      insert(:screener, user: user)
      insert(:chart_configuration, user: user)
      insert(:dashboard, user: user)
      insert(:user_trigger, user: user)
      insert(:watchlist, user: other)

      {:ok, creations} = ClientUsage.creations(user.id, Date.utc_today())
      by_kind = Map.new(creations, &{&1.kind, &1})

      assert by_kind.watchlists.total == 1
      assert by_kind.watchlists.changed_recently == 1
      assert %NaiveDateTime{} = by_kind.watchlists.last_changed_at
      assert by_kind.screeners.total == 1
      assert by_kind.chart_layouts.total == 1
      assert by_kind.dashboards.total == 1
      assert by_kind.sql_queries.total == 0
      assert by_kind.insights.total == 0
      assert by_kind.alerts.total == 1
      assert is_integer(by_kind.alerts.active)

      assert Enum.map(ClientUsage.sort_creations(creations), & &1.kind) ==
               ~w(alerts watchlists screeners chart_layouts dashboards sql_queries insights)a
    end
  end

  describe "labels" do
    test "connection_label/1" do
      assert ClientUsage.connection_label("python-requests/2.32.3") == "Python"

      assert ClientUsage.connection_label("Mozilla/5.0 (compatible; Google-Apps-Script)") ==
               "Google Sheets"

      assert ClientUsage.connection_label("node") == "JavaScript"
      assert ClientUsage.connection_label("Go-http-client/2.0") == "Go"
      assert ClientUsage.connection_label("Mozilla/5.0 (X11; Linux x86_64)") == "Browser"
      assert ClientUsage.connection_label(nil) == "Unknown"
      assert ClientUsage.connection_label("jeeves-ingest") == "jeeves-ingest"
    end

    test "query_label/1" do
      assert ClientUsage.query_label("getMetric|exchange_inflow") == "exchange_inflow"
      assert ClientUsage.query_label("allProjects") == "allProjects"
    end
  end

  describe "summary/4" do
    defp api(attrs) do
      {:ok,
       Map.merge(
         %{
           calls: %{current: 1_000, previous: 1_000},
           errors: 0,
           queries: [%{name: "getMetric|mvrv_usd", current: 1_000, previous: 1_000, errors: 0}],
           assets: [],
           connections: []
         },
         Map.new(attrs)
       )}
    end

    defp web(areas \\ []), do: {:ok, %{areas: areas, sql_runs: %{current: 0, previous: 0}}}

    defp creations(counts) do
      {:ok,
       for {kind, total, active} <- counts do
         %{
           kind: kind,
           label: to_string(kind),
           total: total,
           active: active,
           changed_recently: 0,
           last_changed_at: nil,
           last_fired_at: nil
         }
       end}
    end

    @client %{active_days: 20, active_days_prev: 20, business_reason: :plan, plan_limit: nil}

    test "a steady client gets only the activity line" do
      assert ClientUsage.summary(@client, api([]), web(), creations([])) ==
               ["Active on 20 of the last 30 days."]
    end

    test "a client who dropped a metric they relied on" do
      client = %{@client | active_days: 4}

      queries = [
        %{name: "getMetric|exchange_inflow", current: 0, previous: 2_400, errors: 0},
        %{name: "getMetric|mvrv_usd", current: 600, previous: 1_600, errors: 0}
      ]

      lines =
        ClientUsage.summary(
          client,
          api(calls: %{current: 600, previous: 4_000}, queries: queries),
          web(),
          creations([])
        )

      assert lines == [
               "Active on 4 of the last 30 days, was 20.",
               "API calls down 85%: 600 against 4,000 in the 30 days before.",
               "Stopped calling exchange_inflow, which was 60% of their calls."
             ]
    end

    test "failed calls, a new metric, an upsell and a pricing page visit" do
      queries = [
        %{name: "getMetric|mvrv_usd", current: 1_500, previous: 1_000, errors: 120},
        %{name: "getMetric|nvt", current: 500, previous: 0, errors: 0}
      ]

      client = %{
        @client
        | plan_limit: %{
            upsell?: true,
            upsell_reason: "On pace for 95% of the monthly limit this month"
          }
      }

      lines =
        ClientUsage.summary(
          client,
          api(calls: %{current: 2_000, previous: 1_000}, errors: 120, queries: queries),
          web([%{area: "Pricing page", current: 2, previous: 0}]),
          creations([])
        )

      assert lines == [
               "Active on 20 of the last 30 days.",
               "API calls up 100%: 2,000 against 1,000 in the 30 days before.",
               "6% of API calls failed in the last 30 days, most of them mvrv_usd.",
               "Started calling nvt, now 25% of their calls.",
               "Upsell: On pace for 95% of the monthly limit this month.",
               "Visited the pricing page 2 time(s) in the last 30 days."
             ]
    end

    test "what a Sanbase client built, or that they built nothing" do
      email_client = %{@client | business_reason: :business_email}
      no_api = api(calls: %{current: 0, previous: 0}, queries: [])

      built = creations([{:alerts, 4, 3}, {:watchlists, 2, nil}, {:dashboards, 0, nil}])

      assert List.last(ClientUsage.summary(email_client, no_api, web(), built)) ==
               "Has built 3 active alert(s), 2 watchlist(s)."

      nothing = creations([{:alerts, 1, 0}, {:watchlists, 0, nil}])

      assert List.last(ClientUsage.summary(email_client, no_api, web(), nothing)) ==
               "Has built nothing in Sanbase: no alerts, watchlists or saved charts."

      # An API client with nothing built: not worth a line.
      assert ClientUsage.summary(@client, no_api, web(), nothing) ==
               ["Active on 20 of the last 30 days."]
    end

    test "a part that failed adds nothing" do
      assert ClientUsage.summary(%{}, :error, :error, :error) == []
    end
  end
end
