defmodule Sanbase.Notifications.PriceVolumeDiffTest do
  use Sanbase.DataCase, async: false
  use Mockery

  alias Sanbase.Notifications.PriceVolumeDiff

  import Sanbase.Factory

  @moduletag capture_log: true

  setup do
    [project1: insert(:random_project), project2: insert(:random_project)]
  end

  test "price & volume not diverging", context do
    mock(
      HTTPoison,
      :get,
      {:ok,
       %HTTPoison.Response{
         body:
           "[{\"price_volume_diff\": 0.001, \"price_change\": 0.04, \"volume_change\": 0.03, \"timestamp\": 1516752000}]",
         status_code: 200
       }}
    )

    mock(HTTPoison, :post, {:ok, %HTTPoison.Response{status_code: 204}})

    Sanbase.Mock.prepare_mock(Sanbase.Price, :aggregated_metric_timeseries_data, fn
      slug, :volume_usd, _, _ -> {:ok, %{slug => notification_volume_threshold()}}
    end)
    |> Sanbase.Mock.run_with_mocks(fn ->
      PriceVolumeDiff.exec(context.project1, "USD")

      refute_called(HTTPoison, :post)
    end)
  end

  test "price & volume diverging", context do
    mock(
      HTTPoison,
      :get,
      {:ok,
       %HTTPoison.Response{
         body: """
          [
            #{Sanbase.TechIndicatorsTestResponse.price_volume_diff_prepend_response()},
            {"price_volume_diff": 123.456, "price_change": 0.04862261825993345, "volume_change": -0.030695260272520467, "timestamp": #{
           DateTime.utc_now() |> DateTime.to_unix()
         }}
          ]
         """,
         status_code: 200
       }}
    )

    mock(HTTPoison, :post, {:ok, %HTTPoison.Response{status_code: 204}})

    PriceVolumeDiff.exec(context.project1, "USD")

    Sanbase.Mock.prepare_mock(Sanbase.Price, :aggregated_metric_timeseries_data, fn
      slug, :volume_usd, _, _ -> {:ok, %{slug => notification_volume_threshold()}}
    end)
    |> Sanbase.Mock.prepare_mock2(&Sanbase.GoogleChart.build_embedded_chart/4, [
      %{image: %{url: "url"}}
    ])
    |> Sanbase.Mock.run_with_mocks(fn ->
      PriceVolumeDiff.exec(context.project1, "USD")

      assert_called(HTTPoison, :post)
    end)
  end

  test "volume threshold not met", context do
    mock(
      HTTPoison,
      :get,
      {:ok,
       %HTTPoison.Response{
         body:
           "[{\"price_volume_diff\": 123.456, \"price_change\": 0.04862261825993345, \"volume_change\": -0.030695260272520467, \"timestamp\": 1516752000}]",
         status_code: 200
       }}
    )

    mock(HTTPoison, :post, {:ok, %HTTPoison.Response{status_code: 204}})

    PriceVolumeDiff.exec(context.project2, "USD")

    refute_called(HTTPoison, :post)
  end

  defp notification_volume_threshold() do
    require Sanbase.Utils.Config, as: Config

    {res, _} =
      Config.module_get(Sanbase.Notifications.PriceVolumeDiff, :notification_volume_threshold)
      |> Integer.parse()

    res
  end
end
