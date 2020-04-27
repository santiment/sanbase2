defmodule Sanbase.SocialDominanceTest do
  use SanbaseWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  alias Sanbase.SocialData
  import Sanbase.Factory

  @successful_response_body ~s([
    {"BTC_bitcoin": 5, "EOS_eos": 15, "ETH_ethereum": 5, "datetime": 1523872800},
    {"BTC_bitcoin": 15, "EOS_eos": 5, "ETH_ethereum": 10, "datetime": 1523916000}
  ])

  @successful_response_body_with_no_mentions ~s([
    {"BTC_bitcoin": 0, "EOS_eos": 0, "ETH_ethereum": 0, "datetime": 1523872800},
    {"BTC_bitcoin": 0, "EOS_eos": 0, "ETH_ethereum": 0, "datetime": 1523916000}
  ])

  setup do
    Sanbase.Cache.clear_all()
    project = insert(:project, %{slug: "ethereum", ticker: "ETH"})

    [project: project]
  end

  describe "social_dominance/5" do
    test "response: success" do
      from = ~U[2018-04-16 10:00:00Z]
      to = ~U[2018-04-16 22:00:00Z]

      Sanbase.Mock.prepare_mock2(
        &HTTPoison.get/3,
        {:ok, %HTTPoison.Response{body: @successful_response_body, status_code: 200}}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        result = SocialData.social_dominance(%{slug: "ethereum"}, from, to, "1h", :telegram)

        assert result ==
                 {:ok,
                  [
                    %{dominance: 20, datetime: from},
                    %{dominance: 33.33, datetime: to}
                  ]}
      end)
    end

    test "when computing for all sources" do
      from = ~U[2018-04-16 10:00:00Z]
      to = ~U[2018-04-16 22:00:00Z]

      Sanbase.Mock.prepare_mock2(
        &HTTPoison.get/3,
        {:ok, %HTTPoison.Response{body: @successful_response_body, status_code: 200}}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        result = SocialData.social_dominance(%{slug: "ethereum"}, from, to, "1h", :all)

        assert result ==
                 {:ok,
                  [
                    %{dominance: 20.0, datetime: from},
                    %{dominance: 33.33, datetime: to}
                  ]}
      end)
    end

    test "when there are no mentions for any project" do
      from = ~U[2018-04-16 10:00:00Z]
      to = ~U[2018-04-16 22:00:00Z]

      Sanbase.Mock.prepare_mock2(
        &HTTPoison.get/3,
        {:ok,
         %HTTPoison.Response{body: @successful_response_body_with_no_mentions, status_code: 200}}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        result = SocialData.social_dominance(%{slug: "ethereum"}, from, to, "1h", :telegram)

        assert result ==
                 {:ok, [%{dominance: 0, datetime: from}, %{dominance: 0, datetime: to}]}
      end)
    end

    test "response: 404" do
      Sanbase.Mock.prepare_mock2(
        &HTTPoison.get/3,
        {:ok, %HTTPoison.Response{body: "Some message", status_code: 404}}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        result = fn ->
          SocialData.social_dominance(
            %{slug: "santiment"},
            ~U[2018-04-16 10:00:00Z],
            ~U[2018-04-16 22:00:00Z],
            "1h",
            :telegram
          )
        end

        assert capture_log(result) =~
                 "Error status 404 fetching social dominance for project santiment"
      end)
    end

    test "response: error" do
      Sanbase.Mock.prepare_mock2(
        &HTTPoison.get/3,
        {:error, %HTTPoison.Error{reason: :econnrefused}}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        result = fn ->
          SocialData.social_dominance(
            %{slug: "santiment"},
            ~U[2018-04-16 10:00:00Z],
            ~U[2018-04-16 22:00:00Z],
            "1h",
            :telegram
          )
        end

        assert capture_log(result) =~
                 "Cannot fetch social dominance data for project santiment: :econnrefused\n"
      end)
    end
  end
end
