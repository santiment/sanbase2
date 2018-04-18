defmodule Sanbase.Notifications.PriceVolumeDiffTest do
  use Sanbase.DataCase, async: false
  use Mockery

  alias Sanbase.Notifications.PriceVolumeDiff
  alias Sanbase.Model.Project
  alias Sanbase.Prices.Store
  alias Sanbase.Influxdb.Measurement
  alias Sanbase.Utils.Config

  require Sanbase.Utils.Config

  setup do
    Application.fetch_env!(:sanbase, Sanbase.Prices.Store)
    |> Keyword.get(:database)
    |> Instream.Admin.Database.create()
    |> Store.execute()

    Store.drop_measurement("TEST_USD")
    Store.drop_measurement("TESTNOVOLUME_USD")

    datetime =
      DateTime.utc_now()
      |> DateTime.to_unix(:nanosecond)

    Store.import([
      %Measurement{
        timestamp: datetime,
        fields: %{volume: notification_volume_threshold()},
        name: "TEST_USD"
      }
    ])
  end

  test "price & volume not diverging", _context do
    mock(
      HTTPoison,
      :get,
      {:ok,
       %HTTPoison.Response{
         body:
           "[{\"price_volume_diff\": 0.0, \"price_change\": 0.04862261825993345, \"volume_change\": 0.030695260272520467, \"timestamp\": 1516752000}]",
         status_code: 200
       }}
    )

    mock(
      HTTPoison,
      :post,
      {:ok, %HTTPoison.Response{status_code: 204}}
    )

    PriceVolumeDiff.exec(%Project{name: "TestProj", ticker: "TEST"}, "USD")

    refute_called(HTTPoison, :post)
  end

  test "price & volume diverging", _context do
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

    mock(
      HTTPoison,
      :post,
      {:ok, %HTTPoison.Response{status_code: 204}}
    )

    PriceVolumeDiff.exec(%Project{name: "TestProj", ticker: "TEST"}, "USD")

    assert_called(HTTPoison, post: 3)
  end

  test "volume threshold not met", _context do
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

    mock(
      HTTPoison,
      :post,
      {:ok, %HTTPoison.Response{status_code: 204}}
    )

    PriceVolumeDiff.exec(%Project{name: "TestProj", ticker: "TESTNOVOLUME"}, "USD")

    refute_called(HTTPoison, :post)
  end

  defp notification_volume_threshold() do
    {res, _} =
      Config.module_get(Sanbase.Notifications.PriceVolumeDiff, :notification_volume_threshold)
      |> Integer.parse()

    res
  end
end
