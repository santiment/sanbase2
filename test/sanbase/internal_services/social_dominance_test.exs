defmodule Sanbase.SocialDominanceTest do
  use SanbaseWeb.ConnCase, async: false

  import Mockery
  import ExUnit.CaptureLog

  alias Sanbase.TechIndicators
  import Sanbase.Factory

  setup do
    project =
      insert(:project, %{
        coinmarketcap_id: "santiment",
        ticker: "SAN",
        main_contract_address: "0x123"
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
             "[{\"mentions_count\": 5, \"timestamp\": 1523876400}, {\"mentions_count\": 15, \"timestamp\": 1523880000}]",
           status_code: 200
         }}
      )

      result =
        TechIndicators.social_dominance(
          "santiment",
          DateTime.from_unix!(from),
          DateTime.from_unix!(to),
          "1h",
          :telegram_discussion_overview
        )

      assert result ==
               {:ok,
                [
                  %{
                    dominance: 5,
                    datetime: DateTime.from_unix!(from)
                  },
                  %{
                    dominance: 15,
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
        TechIndicators.social_dominance(
          "santiment",
          DateTime.from_unix!(1_523_876_400),
          DateTime.from_unix!(1_523_880_000),
          "1h",
          :telegram_discussion_overview
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
        TechIndicators.social_dominance(
          "santiment",
          DateTime.from_unix!(1_523_876_400),
          DateTime.from_unix!(1_523_880_000),
          "1h",
          :telegram_discussion_overview
        )
      end

      assert capture_log(result) =~
               "Cannot fetch social dominance data for project santiment: :econnrefused\n"
    end
  end
end
