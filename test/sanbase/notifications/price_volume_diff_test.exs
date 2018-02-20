defmodule Sanbase.Notifications.PriceVolumeDiffTest do
    use Sanbase.DataCase, async: false
    use Mockery
  
    alias Sanbase.Notifications.PriceVolumeDiff
    alias Sanbase.Model.Project
  
    test "price & volume not diverging", _context do
      mock(
        HTTPoison,
        :get,
        {:ok,
        %HTTPoison.Response{
          body: "[{\"price_volume_diff\": 0.0, \"price_change\": 0.04862261825993345, \"volume_change\": 0.030695260272520467, \"timestamp\": 1516752000}]",
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
          body: "[{\"price_volume_diff\": 123.456, \"price_change\": 0.04862261825993345, \"volume_change\": -0.030695260272520467, \"timestamp\": 1516752000}]",
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
  end
  