defmodule Sanbase.SocialVolumeTest do
  use SanbaseWeb.ConnCase, async: false
  import Mockery
  import ExUnit.CaptureLog

  alias Sanbase.SocialData.SocialVolume
  alias Sanbase.SocialData.SocialHelper
  alias Sanbase.SocialData.MetricAdapter
  import Sanbase.Factory

  setup do
    project =
      insert(:project, %{
        slug: "santiment",
        ticker: "SAN",
        main_contract_address: "0x123"
      })

    [
      project: project
    ]
  end

  describe "social_volume/5" do
    test "response with slug: success" do
      from = ~U[2018-04-16 11:00:00Z]
      to = ~U[2018-04-16 12:00:00Z]

      mock(
        HTTPoison,
        :get,
        {:ok,
         %HTTPoison.Response{
           body: "{\"data\": {\"2018-04-16T11:00:00Z\": 5, \"2018-04-16T12:00:00Z\": 15}}",
           status_code: 200
         }}
      )

      result = SocialVolume.social_volume(%{slug: "santiment"}, from, to, "1h", :telegram)

      assert result ==
               {:ok,
                [
                  %{mentions_count: 5, datetime: from},
                  %{mentions_count: 15, datetime: to}
                ]}
    end

    test "response with slug: 404" do
      from = ~U[2018-04-16 11:00:00Z]
      to = ~U[2018-04-16 12:00:00Z]

      mock(HTTPoison, :get, {:ok, %HTTPoison.Response{body: "Some message", status_code: 404}})

      assert capture_log(fn ->
               SocialVolume.social_volume(%{slug: "santiment"}, from, to, "1h", :telegram)
             end) =~
               "Error status 404 fetching social volume for %{slug: \"santiment\"}\n"
    end

    test "response with slug: error" do
      from = ~U[2018-04-16 11:00:00Z]
      to = ~U[2018-04-16 12:00:00Z]

      mock(HTTPoison, :get, {:error, %HTTPoison.Error{reason: :econnrefused}})

      assert capture_log(fn ->
               SocialVolume.social_volume(%{slug: "santiment"}, from, to, "1h", :telegram)
             end) =~
               "Cannot fetch social volume data for %{slug: \"santiment\"}: :econnrefused\n"
    end

    test "response with text: success" do
      from = ~U[2018-04-16 11:00:00Z]
      to = ~U[2018-04-16 12:00:00Z]

      mock(
        HTTPoison,
        :get,
        {:ok,
         %HTTPoison.Response{
           body: "{\"data\": {\"2018-04-16T11:00:00Z\": 1, \"2018-04-16T12:00:00Z\": 0}}",
           status_code: 200
         }}
      )

      result = SocialVolume.social_volume(%{text: "btc moon"}, from, to, "6h", :telegram)

      assert result ==
               {:ok,
                [
                  %{datetime: from, mentions_count: 1},
                  %{datetime: to, mentions_count: 0}
                ]}
    end

    test "response with text: 404" do
      from = ~U[2018-04-16 11:00:00Z]
      to = ~U[2018-04-16 12:00:00Z]

      mock(HTTPoison, :get, {:ok, %HTTPoison.Response{body: "Some message", status_code: 404}})

      assert capture_log(fn ->
               SocialVolume.social_volume(%{text: "btc moon"}, from, to, "6h", :reddit)
             end) =~
               "Error status 404 fetching social volume for %{text: \"btc moon\"}\n"
    end

    test "response with text: error" do
      from = ~U[2018-04-16 11:00:00Z]
      to = ~U[2018-04-16 12:00:00Z]

      mock(HTTPoison, :get, {:error, %HTTPoison.Error{reason: :econnrefused}})

      assert capture_log(fn ->
               SocialVolume.social_volume(%{text: "btc moon"}, from, to, "6h", :discord)
             end) =~
               "Cannot fetch social volume data for %{text: \"btc moon\"}: :econnrefused\n"
    end

    test "all sources in total" do
      sources =
        MetricAdapter.available_metrics()
        |> Enum.filter(fn
          "social_volume_total" -> false
          "social_volume_" <> _source -> true
          _ -> false
        end)
        |> Enum.map(fn "social_volume_" <> source -> source end)

      expected_sources =
        SocialHelper.sources()
        |> Enum.map(fn
          source -> Atom.to_string(source)
        end)

      # newsapi_crypto is added as a social volume metric for now.
      # if we add it to the sources list, it will define the sentiment
      # metrics and they are not supported. Fix when all newsapi_crypto
      # metrics are introduced
      expected_sources = ["newsapi_crypto"] ++ expected_sources

      assert expected_sources |> Enum.sort() == sources |> Enum.sort()
    end
  end
end
