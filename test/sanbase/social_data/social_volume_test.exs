defmodule Sanbase.SocialVolumeTest do
  use SanbaseWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Mockery
  import Sanbase.Factory

  alias Sanbase.SocialData.MetricAdapter
  alias Sanbase.SocialData.SocialHelper
  alias Sanbase.SocialData.SocialVolume

  setup do
    project =
      insert(:project, %{
        slug: "santiment",
        ticker: "SAN",
        main_contract_address: "0x4efb548a2cb8f0af7c591cef21053f6875b5d38f"
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
           body: ~s({"data": {"2018-04-16T11:00:00Z": 5, "2018-04-16T12:00:00Z": 15}}),
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
           body: ~s({"data": {"2018-04-16T11:00:00Z": 1, "2018-04-16T12:00:00Z": 0}}),
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
        Enum.map(SocialHelper.sources(), fn
          source -> Atom.to_string(source)
        end)

      assert Enum.sort(expected_sources) == Enum.sort(sources)
    end
  end
end
