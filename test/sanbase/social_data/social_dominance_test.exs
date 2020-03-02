defmodule Sanbase.SocialDominanceTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Mockery
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
    project = insert(:project, %{slug: "ethereum", ticker: "ETH"})

    [project: project]
  end

  describe "social_dominance/5" do
    test "response: success" do
      from = ~U[2018-04-16 10:00:00Z]
      to = ~U[2018-04-16 22:00:00Z]

      mock(
        HTTPoison,
        :get,
        {:ok, %HTTPoison.Response{body: @successful_response_body, status_code: 200}}
      )

      result = SocialData.social_dominance(%{slug: "ethereum"}, from, to, "1h", :telegram)

      assert result ==
               {:ok,
                [
                  %{dominance: 20, datetime: from},
                  %{dominance: 33.33, datetime: to}
                ]}
    end

    test "when computing for all sources" do
      from = ~U[2018-04-16 10:00:00Z]
      to = ~U[2018-04-16 22:00:00Z]

      with_mock(HTTPoison, [],
        get: fn _, _, _ ->
          {:ok,
           %HTTPoison.Response{
             body: @successful_response_body,
             status_code: 200
           }}
        end
      ) do
        result = SocialData.social_dominance(%{slug: "ethereum"}, from, to, "1h", :all)

        assert result ==
                 {:ok,
                  [
                    %{dominance: 20.0, datetime: from},
                    %{dominance: 33.33, datetime: to}
                  ]}
      end
    end

    test "when there are no mentions for any project" do
      from = ~U[2018-04-16 10:00:00Z]
      to = ~U[2018-04-16 22:00:00Z]

      mock(
        HTTPoison,
        :get,
        {:ok,
         %HTTPoison.Response{body: @successful_response_body_with_no_mentions, status_code: 200}}
      )

      result = SocialData.social_dominance(%{slug: "ethereum"}, from, to, "1h", :telegram)

      assert result ==
               {:ok, [%{dominance: 0, datetime: from}, %{dominance: 0, datetime: to}]}
    end

    test "response: 404" do
      mock(HTTPoison, :get, {:ok, %HTTPoison.Response{body: "Some message", status_code: 404}})

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
    end

    test "response: error" do
      mock(HTTPoison, :get, {:error, %HTTPoison.Error{reason: :econnrefused}})

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
    end
  end
end
