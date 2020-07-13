defmodule Sanbase.SocialDominanceTest do
  use SanbaseWeb.ConnCase, async: false
  import Mockery
  import ExUnit.CaptureLog

  alias Sanbase.SocialData.SocialDominance
  alias Sanbase.SocialData.SocialHelper
  alias Sanbase.SocialData.MetricAdapter
  import Sanbase.Factory

  setup do
    Sanbase.Cache.clear_all()
    project = insert(:project, %{slug: "ethereum", ticker: "ETH"})

    [project: project]
  end

  describe "social_dominance/5" do
    test "response with slug: success" do
      from = ~U[2018-04-16 11:00:00Z]
      to = ~U[2018-04-16 12:00:00Z]

      Sanbase.Mock.prepare_mock2(
        &HTTPoison.get/3,
        {:ok,
         %HTTPoison.Response{
           body: "{\"data\": {\"2018-04-16T11:00:00Z\": 0.5, \"2018-04-16T12:00:00Z\": 1}}",
           status_code: 200
         }}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        result = SocialDominance.social_dominance(%{slug: "santiment"}, from, to, "1h", :telegram)

        assert result ==
                 {:ok,
                  [
                    %{dominance: 0.5, datetime: from},
                    %{dominance: 1, datetime: to}
                  ]}
      end)
    end

    test "response with slug: 404" do
      Sanbase.Mock.prepare_mock2(
        &HTTPoison.get/3,
        {:ok, %HTTPoison.Response{body: "Some message", status_code: 404}}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        result = fn ->
          SocialDominance.social_dominance(
            %{slug: "santiment"},
            ~U[2018-04-16 11:00:00Z],
            ~U[2018-04-16 12:00:00Z],
            "1h",
            :telegram
          )
        end

        assert capture_log(result) =~
                 "Error status 404 fetching social dominance for project with slug \"santiment\"}\n"
      end)
    end

    test "response with slug: error" do
      Sanbase.Mock.prepare_mock2(
        &HTTPoison.get/3,
        {:error, %HTTPoison.Error{reason: :econnrefused}}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        result = fn ->
          SocialDominance.social_dominance(
            %{slug: "santiment"},
            ~U[2018-04-16 10:00:00Z],
            ~U[2018-04-16 22:00:00Z],
            "1h",
            :telegram
          )
        end

        assert capture_log(result) =~
                 "Cannot fetch social dominance data for project with slug \"santiment\"}: :econnrefused\n"
      end)
    end
  end
end
