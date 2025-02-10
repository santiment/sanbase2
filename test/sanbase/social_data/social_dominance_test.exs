defmodule Sanbase.SocialDominanceTest do
  use SanbaseWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Sanbase.Factory

  alias Sanbase.SocialData.SocialDominance

  setup do
    Sanbase.Cache.clear_all()
    project = insert(:project, %{slug: "ethereum", ticker: "ETH"})

    [project: project]
  end

  describe "social_dominance/5" do
    test "response with slug: success" do
      from = ~U[2018-04-16 11:00:00Z]
      to = ~U[2018-04-16 12:00:00Z]

      (&HTTPoison.get/3)
      |> Sanbase.Mock.prepare_mock2(
        {:ok,
         %HTTPoison.Response{
           body: ~s({"data": {"2018-04-16T11:00:00Z": 0.5, "2018-04-16T12:00:00Z": 1}}),
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
      (&HTTPoison.get/3)
      |> Sanbase.Mock.prepare_mock2({:ok, %HTTPoison.Response{body: "Some message", status_code: 404}})
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
      (&HTTPoison.get/3)
      |> Sanbase.Mock.prepare_mock2({:error, %HTTPoison.Error{reason: :econnrefused}})
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
