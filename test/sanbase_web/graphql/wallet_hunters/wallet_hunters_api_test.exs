defmodule SanbaseWeb.Graphql.WalletHuntersApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)
    proposal = insert(:wallet_hunters_proposal, user: user)
    {:ok, user: user, proposal: proposal}
  end

  test "Fetch all proposals" do
    Sanbase.Mock.prepare_mock2(&Ethereumex.HttpClient.eth_call/1, all_proposals_resp())
    |> Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: labels_rows()}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result = execute_query(build_conn(), wallet_hunters_query(), "walletHuntersProposals")

      assert result == query_response()
    end)
  end

  test "Fetch all proposals sorted and paginated" do
    Sanbase.Mock.prepare_mock2(&Ethereumex.HttpClient.eth_call/1, all_proposals_resp())
    |> Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: labels_rows()}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      selector = %{sort_by: %{field: "created_at", direction: :desc}, page: 1, page_size: 2}

      result =
        execute_query(build_conn(), wallet_hunters_query(selector), "walletHuntersProposals")

      assert result == query_response() |> Enum.sort_by(& &1["createdAt"], :desc) |> Enum.take(2)
    end)
  end

  test "Fetch all proposals filtered" do
    Sanbase.Mock.prepare_mock2(&Ethereumex.HttpClient.eth_call/1, all_proposals_resp())
    |> Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: labels_rows()}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      selector = %{
        filter: [
          %{field: "state", value: "active"},
          %{field: "address", value: "0x26caae548b7cecf98da12ccaaa633d6d140447aa"}
        ]
      }

      result =
        execute_query(build_conn(), wallet_hunters_query(selector), "walletHuntersProposals")

      assert result == query_response() |> Enum.take(-1)
    end)
  end

  defp wallet_hunters_query(selector \\ %{}) do
    selector = map_to_input_object_str(selector, map_as_input_object: true)

    """
    {
      walletHuntersProposals(
        selector: #{selector}
      ) {
        proposalId
        user {
          email
        }
        title
        text
        address
        labels {
          name
        }
        reward
        state
        isRewardClaimed
        createdAt
        finishAt
        votesFor
        votesAgainst
        sheriffsRewardShare
        fixedSheriffReward
      }
    }
    """
  end

  defp labels_rows() do
    [
      ["0x26caae548b7cecf98da12ccaaa633d6d140447aa", "DEX Trader", "{\"owner\": \"\"}"]
    ]
  end

  def all_proposals_resp do
    {:ok,
     "0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cb8c7409fe98a396f32d6cff4736bedc7b60008c0000000000000000000000000000000000000000000000056bc75e2d631000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000605a50c800000000000000000000000000000000000000000000000000000000605ba2480000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007d00000000000000000000000000000000000000000000000008ac7230489e800000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000cb8c7409fe98a396f32d6cff4736bedc7b60008c000000000000000000000000000000000000000000000005f68e8131ecf800000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000605b005700000000000000000000000000000000000000000000000000000000605c51d70000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007d00000000000000000000000000000000000000000000000008ac7230489e80000000000000000000000000000000000000000000000000000000000000000000200000000000000000000000026caae548b7cecf98da12ccaaa633d6d140447aa00000000000000000000000000000000000000000000029d01c7829467b400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000605c4dac00000000000000000000000000000000000000000000000000000000605d9f2c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007d00000000000000000000000000000000000000000000000008ac7230489e80000"}
  end

  def query_response do
    [
      %{
        "address" => "0xcb8c7409fe98a396f32d6cff4736bedc7b60008c",
        "isRewardClaimed" => false,
        "createdAt" => "2021-03-23T20:34:16Z",
        "finishAt" => "2021-03-24T20:34:16Z",
        "fixedSheriffReward" => 10.0,
        "labels" => [],
        "proposalId" => "0",
        "reward" => 100.0,
        "sheriffsRewardShare" => 2.0e3,
        "state" => "DECLINED",
        "text" => nil,
        "title" => nil,
        "user" => nil,
        "votesAgainst" => 0.0,
        "votesFor" => 0.0
      },
      %{
        "address" => "0xcb8c7409fe98a396f32d6cff4736bedc7b60008c",
        "isRewardClaimed" => false,
        "createdAt" => "2021-03-24T09:03:19Z",
        "finishAt" => "2021-03-25T09:03:19Z",
        "fixedSheriffReward" => 10.0,
        "labels" => [],
        "proposalId" => "1",
        "reward" => 110.0,
        "sheriffsRewardShare" => 2.0e3,
        "state" => "DECLINED",
        "text" => nil,
        "title" => nil,
        "user" => nil,
        "votesAgainst" => 0.0,
        "votesFor" => 0.0
      },
      %{
        "address" => "0x26caae548b7cecf98da12ccaaa633d6d140447aa",
        "isRewardClaimed" => false,
        "createdAt" => "2021-03-25T08:45:32Z",
        "finishAt" => "2021-03-26T08:45:32Z",
        "fixedSheriffReward" => 10.0,
        "labels" => [%{"name" => "DEX Trader"}],
        "proposalId" => "2",
        "reward" => 12341.0,
        "sheriffsRewardShare" => 2.0e3,
        "state" => "ACTIVE",
        "text" => "text",
        "title" => "title",
        "user" => %{"email" => "<email hidden>"},
        "votesAgainst" => 0.0,
        "votesFor" => 0.0
      }
    ]
  end
end
