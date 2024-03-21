defmodule Sanbase.Billing.ApiIncludeIncompleteDataFlagTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import Sanbase.TestHelpers
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Accounts.Apikey
  alias Sanbase.Metric

  @moduletag capture_log: true

  setup_all_with_mocks([
    {Sanbase.Metric, [:passthrough], [timeseries_data: fn _, _, _, _, _, _ -> metric_resp() end]}
  ]) do
    []
  end

  setup do
    user = insert(:user)
    insert(:subscription_custom, user: user)

    project = insert(:random_erc20_project)

    {:ok, apikey} = Apikey.generate_apikey(user)
    conn = setup_apikey_auth(build_conn(), apikey)

    [user: user, conn: conn, project: project]
  end

  test "incomplete data is not included when flag is false", context do
    %{conn: conn, project: project} = context
    to = Timex.now()
    from = Timex.shift(to, days: -30)
    end_of_previous_day = Timex.beginning_of_day(to) |> Timex.shift(microseconds: -1)
    metric = "nvt"
    interval = "1d"

    query = metric_query(metric, project.slug, from, to, interval, false)
    execute_query(conn, query, "getMetric")

    refute called(Metric.timeseries_data(metric, %{slug: project.slug}, from, to, interval, :_))

    assert called(
             Metric.timeseries_data(
               metric,
               %{slug: project.slug},
               from,
               end_of_previous_day,
               interval,
               :_
             )
           )
  end

  test "incomplete data is included when flag is true", context do
    %{conn: conn, project: project} = context
    to = Timex.now()
    from = Timex.shift(to, days: -30)
    end_of_previous_day = Timex.beginning_of_day(to) |> Timex.shift(microseconds: -1)
    metric = "nvt"
    interval = "1d"

    query = metric_query(metric, project.slug, from, to, interval, true)
    execute_query(conn, query, "getMetric")

    assert called(Metric.timeseries_data(metric, %{slug: project.slug}, from, to, interval, :_))

    refute called(
             Metric.timeseries_data(
               metric,
               %{slug: project.slug},
               from,
               end_of_previous_day,
               interval,
               :_
             )
           )
  end

  test "returns error if both from and to are today", context do
    %{conn: conn, project: project} = context
    beginning_of_day = Timex.beginning_of_day(Timex.now())
    from = Timex.shift(beginning_of_day, hours: 5)
    to = Timex.shift(beginning_of_day, hours: 10)
    metric = "nvt"
    interval = "1h"

    query = metric_query(metric, project.slug, from, to, interval, false)

    error_message = execute_query_with_error(conn, query, "getMetric")
    assert error_message =~ "Can't fetch nvt"
    assert error_message =~ "could have incomplete data"
    assert error_message =~ "you can pass the flag `includeIncompleteData: true` "
  end

  # Private functions

  defp metric_query(metric, slug, from, to, interval, include_incomplete_data) do
    """
      {
        getMetric(metric: "#{metric}") {
          timeseriesData(
            slug: "#{slug}"
            from: "#{from}"
            to: "#{to}"
            interval: "#{interval}"
            includeIncompleteData: #{include_incomplete_data}){
              datetime
              value
          }
        }
      }
    """
  end

  defp metric_resp() do
    {:ok,
     [
       %{value: 10.0, datetime: ~U[2019-01-01 00:00:00Z]},
       %{value: 20.0, datetime: ~U[2019-01-02 00:00:00Z]}
     ]}
  end
end
