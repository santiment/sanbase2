defmodule Sanbase.SocialDominanceTest do
  use SanbaseWeb.ConnCase, async: false

  import Mockery
  import ExUnit.CaptureLog

  alias Sanbase.SocialData
  import Sanbase.Factory

  setup do
    project =
      insert(:project, %{
        coinmarketcap_id: "ethereum",
        ticker: "ETH"
      })

    [
      project: project
    ]
  end

  describe "social_dominance/5" do
    test "response: success" do
      from = 1_523_876_400
      to = 1_523_880_000

      mock(
        HTTPoison,
        :get,
        {:ok,
         %HTTPoison.Response{
           body:
             "[{\"BTC_bitcoin\": 5, \"EOS_eos\": 15, \"ETH_ethereum\": 5, \"datetime\": 1523876400}, {\"BTC_bitcoin\": 15, \"EOS_eos\": 5, \"ETH_ethereum\": 10, \"datetime\": 1523880000}]",
           status_code: 200
         }}
      )

      result =
        SocialData.social_dominance(
          "ethereum",
          DateTime.from_unix!(from),
          DateTime.from_unix!(to),
          "1h",
          :telegram
        )

      assert result ==
               {:ok,
                [
                  %{
                    dominance: 5 * 100 / 25,
                    datetime: DateTime.from_unix!(from)
                  },
                  %{
                    dominance: 10 * 100 / 30,
                    datetime: DateTime.from_unix!(to)
                  }
                ]}
    end

    test "when there are no mentions for any project" do
      from = 1_523_876_400
      to = 1_523_880_000

      mock(
        HTTPoison,
        :get,
        {:ok,
         %HTTPoison.Response{
           body:
             "[{\"BTC_bitcoin\": 0, \"EOS_eos\": 0, \"ETH_ethereum\": 0, \"datetime\": 1523876400}, {\"BTC_bitcoin\": 0, \"EOS_eos\": 0, \"ETH_ethereum\": 0, \"datetime\": 1523880000}]",
           status_code: 200
         }}
      )

      result =
        SocialData.social_dominance(
          "ethereum",
          DateTime.from_unix!(from),
          DateTime.from_unix!(to),
          "1h",
          :telegram
        )

      assert result ==
               {:ok,
                [
                  %{
                    dominance: 0,
                    datetime: DateTime.from_unix!(from)
                  },
                  %{
                    dominance: 0,
                    datetime: DateTime.from_unix!(to)
                  }
                ]}
    end

    test "response: 404" do
      mock(
        HTTPoison,
        :get,
        {:ok,
         %HTTPoison.Response{
           body: "Some message",
           status_code: 404
         }}
      )

      result = fn ->
        SocialData.social_dominance(
          "santiment",
          DateTime.from_unix!(1_523_876_400),
          DateTime.from_unix!(1_523_880_000),
          "1h",
          :telegram
        )
      end

      assert capture_log(result) =~
               "Error status 404 fetching social dominance for project santiment"
    end

    test "response: error" do
      mock(
        HTTPoison,
        :get,
        {:error,
         %HTTPoison.Error{
           reason: :econnrefused
         }}
      )

      result = fn ->
        SocialData.social_dominance(
          "santiment",
          DateTime.from_unix!(1_523_876_400),
          DateTime.from_unix!(1_523_880_000),
          "1h",
          :telegram
        )
      end

      assert capture_log(result) =~
               "Cannot fetch social dominance data for project santiment: :econnrefused\n"
    end
  end
end
