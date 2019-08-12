defmodule Sanbase.Clickhouse.V2ClickhouseMetricTest do
  use Sanbase.DataCase

  import Mock
  import Sanbase.Factory
  import Sanbase.DateTimeUtils, only: [from_iso8601_to_unix!: 1, from_iso8601!: 1]

  alias Sanbase.Clickhouse.Metric

  test "can fetch all available metrics" do
    to = Timex.now()
    from = Timex.shift(to, days: -30)
    to_unix = DateTime.to_unix(to)
    from_unix = DateTime.to_unix(from)

    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [from_unix, 10.0],
             [to_unix, 20.0]
           ]
         }}
      end do
      {:ok, metrics} = Metric.available_metrics()

      results =
        for metric <- metrics do
          Metric.get(metric, "santiment", from, to, "1d", :avg)
        end

      assert Enum.all?(results, &match?({:ok, _}, &1))
    end
  end

  test "cannot fetch available metrics that are not in the available list" do
    to = Timex.now()
    from = Timex.shift(to, days: -30)
    to_unix = DateTime.to_unix(to)
    from_unix = DateTime.to_unix(from)

    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [from_unix, 10.0],
             [to_unix, 20.0]
           ]
         }}
      end do
      {:ok, metrics} = Metric.available_metrics()
      rand_metrics = Enum.map(1..100, fn _ -> rand_str() end)
      rand_metrics = rand_metrics -- metrics

      results =
        for metric <- rand_metrics do
          Metric.get(metric, "santiment", from, to, "1d", :avg)
        end

      assert Enum.all?(results, &match?({:error, _}, &1))
    end
  end

  test "can use all available aggregations" do
    to = Timex.now()
    from = Timex.shift(to, days: -30)
    to_unix = DateTime.to_unix(to)
    from_unix = DateTime.to_unix(from)

    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [from_unix, 10.0],
             [to_unix, 20.0]
           ]
         }}
      end do
      # Fetch some available metric
      {:ok, [metric | _]} = Metric.available_metrics()
      {:ok, aggregations} = Metric.available_aggregations()

      results =
        for aggregation <- aggregations do
          Metric.get(metric, "santiment", from, to, "1d", aggregation)
        end

      assert Enum.all?(results, &match?({:ok, _}, &1))
    end
  end

  test "cannot use aggregation that is not available" do
    to = Timex.now()
    from = Timex.shift(to, days: -30)
    to_unix = DateTime.to_unix(to)
    from_unix = DateTime.to_unix(from)

    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [from_unix, 10.0],
             [to_unix, 20.0]
           ]
         }}
      end do
      # Fetch some available metric
      {:ok, [metric | _]} = Metric.available_metrics()
      {:ok, aggregations} = Metric.available_aggregations()
      rand_aggregations = Enum.map(1..10, fn _ -> rand_str() |> String.to_atom() end)
      rand_aggregations = rand_aggregations -- aggregations

      results =
        for aggregation <- rand_aggregations do
          Metric.get(metric, "santiment", from, to, "1d", aggregation)
        end

      assert Enum.all?(results, &match?({:error, _}, &1))
    end
  end

  test "fetch a single metric" do
    dt1_str = "2019-01-01T00:00:00Z"
    dt2_str = "2019-01-02T00:00:00Z"
    dt3_str = "2019-01-03T00:00:00Z"

    with_mock Sanbase.ClickhouseRepo,
      query: fn _, _ ->
        {:ok,
         %{
           rows: [
             [from_iso8601_to_unix!(dt1_str), 10.0],
             [from_iso8601_to_unix!(dt2_str), 20.0],
             [from_iso8601_to_unix!(dt3_str), 50.0]
           ]
         }}
      end do
      # Fetch some available metric
      {:ok, [metric | _]} = Metric.available_metrics()

      result =
        Metric.get(
          metric,
          "santiment",
          from_iso8601!(dt1_str),
          from_iso8601!(dt3_str),
          "1d",
          :avg
        )

      assert result ==
               {:ok,
                [
                  %{value: 10.0, datetime: from_iso8601!(dt1_str)},
                  %{value: 20.0, datetime: from_iso8601!(dt2_str)},
                  %{value: 50.0, datetime: from_iso8601!(dt3_str)}
                ]}
    end
  end
end
