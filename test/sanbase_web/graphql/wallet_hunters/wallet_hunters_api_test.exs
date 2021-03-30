defmodule SanbaseWeb.Graphql.WalletHuntersApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)
    proposal = insert(:wallet_hunters_proposal, user: user)
    conn = setup_jwt_auth(build_conn(), user)
    {:ok, conn: conn, user: user, proposal: proposal}
  end

  test "Create proposal" do
    mock_fun =
      [
        fn -> {:ok, %{rows: labels_rows()}} end,
        fn -> {:ok, %{rows: labels_rows()}} end
      ]
      |> Sanbase.Mock.wrap_consecutives(arity: 2)

    Sanbase.Mock.prepare_mock2(&Ethereumex.HttpClient.eth_call/1, proposal_resp())
    |> Sanbase.Mock.prepare_mock(Sanbase.ClickhouseRepo, :query, mock_fun)
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        execute_mutation(build_conn(), create_proposal_mutation(), "createWalletHunterProposal")

      assert result == %{
               "hunterAddress" => "0xcb8c7409fe98a396f32d6cff4736bedc7b60008c",
               "createdAt" => "2021-03-24T09:03:19Z",
               "finishAt" => "2021-03-25T09:03:19Z",
               "fixedSheriffReward" => 10.0,
               "isRewardClaimed" => false,
               "proposalId" => "1",
               "reward" => 110.0,
               "sheriffsRewardShare" => 2.0e3,
               "state" => "DECLINED",
               "text" => "t",
               "title" => "t2",
               "user" => nil,
               "votesAgainst" => 0.0,
               "votesFor" => 0.0,
               "hunterAddressLabels" => [],
               "proposedAddress" => "0x11111109fe98a396f32d6cff4736bedc7b60008c",
               "proposedAddressLabels" => [%{"name" => "DEX Trader2"}],
               "userLabels" => ["test label1", "test label 2"]
             }
    end)
  end

  test "Create proposal with logged in user", context do
    Sanbase.Mock.prepare_mock2(&Ethereumex.HttpClient.eth_call/1, proposal_resp())
    |> Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: labels_rows()}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        execute_mutation(context.conn, create_proposal_mutation(), "createWalletHunterProposal")

      assert result == %{
               "createdAt" => "2021-03-24T09:03:19Z",
               "finishAt" => "2021-03-25T09:03:19Z",
               "fixedSheriffReward" => 10.0,
               "isRewardClaimed" => false,
               "proposalId" => "1",
               "reward" => 110.0,
               "sheriffsRewardShare" => 2.0e3,
               "state" => "DECLINED",
               "text" => "t",
               "title" => "t2",
               "user" => %{"email" => context.user.email},
               "votesAgainst" => 0.0,
               "votesFor" => 0.0,
               "hunterAddress" => "0xcb8c7409fe98a396f32d6cff4736bedc7b60008c",
               "hunterAddressLabels" => [],
               "proposedAddress" => "0x11111109fe98a396f32d6cff4736bedc7b60008c",
               "proposedAddressLabels" => [%{"name" => "DEX Trader2"}],
               "userLabels" => ["test label1", "test label 2"]
             }
    end)
  end

  test "Create proposal with hunter address that is in EthAccount" do
    Sanbase.Mock.prepare_mock2(&Ethereumex.HttpClient.eth_call/1, proposal_resp())
    |> Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: labels_rows()}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      user =
        insert(:user,
          eth_accounts: [
            %Sanbase.Accounts.EthAccount{address: "0xcb8c7409fe98a396f32d6cff4736bedc7b60008c"}
          ]
        )

      conn = setup_jwt_auth(build_conn(), user)

      result = execute_mutation(conn, create_proposal_mutation(), "createWalletHunterProposal")

      assert result == %{
               "createdAt" => "2021-03-24T09:03:19Z",
               "finishAt" => "2021-03-25T09:03:19Z",
               "fixedSheriffReward" => 10.0,
               "hunterAddress" => "0xcb8c7409fe98a396f32d6cff4736bedc7b60008c",
               "hunterAddressLabels" => [],
               "isRewardClaimed" => false,
               "proposalId" => "1",
               "proposedAddress" => "0x11111109fe98a396f32d6cff4736bedc7b60008c",
               "proposedAddressLabels" => [%{"name" => "DEX Trader2"}],
               "reward" => 110.0,
               "sheriffsRewardShare" => 2.0e3,
               "state" => "DECLINED",
               "text" => "t",
               "title" => "t2",
               "user" => %{"email" => user.email},
               "userLabels" => ["test label1", "test label 2"],
               "votesAgainst" => 0.0,
               "votesFor" => 0.0
             }
    end)
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
          %{field: "hunter_address", value: "0x26caae548b7cecf98da12ccaaa633d6d140447aa"}
        ]
      }

      result =
        execute_query(build_conn(), wallet_hunters_query(selector), "walletHuntersProposals")

      assert result == query_response() |> Enum.take(-1)
    end)
  end

  defp create_proposal_mutation do
    """
    mutation {
      createWalletHunterProposal(
        proposalId:1,
        text:"t",
        title:"t2",
        hunterAddress:"0xcb8c7409fe98a396f32d6cff4736bedc7b60008c",
        proposedAddress:"0x11111109fe98a396f32d6cff4736bedc7b60008c",
        userLabels: ["test label1", "test label 2"]
      ) {
        proposalId
        user {
          email
        }
        title
        text
        hunterAddress
        hunterAddressLabels {
          name
        }
        proposedAddress
        proposedAddressLabels {
          name
        }
        userLabels
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
        hunterAddress
        hunterAddressLabels {
          name
        }
        proposedAddress
        proposedAddressLabels {
          name
        }
        userLabels
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
      ["0x26caae548b7cecf98da12ccaaa633d6d140447aa", "DEX Trader", "{\"owner\": \"\"}"],
      ["0x11111109fe98a396f32d6cff4736bedc7b60008c", "DEX Trader2", "{\"owner\": \"\"}"]
    ]
  end

  defp proposal_resp do
    {:ok,
     "0x0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000cb8c7409fe98a396f32d6cff4736bedc7b60008c000000000000000000000000000000000000000000000005f68e8131ecf800000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000605b005700000000000000000000000000000000000000000000000000000000605c51d70000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007d00000000000000000000000000000000000000000000000008ac7230489e80000"}
  end

  def all_proposals_resp do
    {:ok,
     "0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cb8c7409fe98a396f32d6cff4736bedc7b60008c0000000000000000000000000000000000000000000000056bc75e2d631000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000605a50c800000000000000000000000000000000000000000000000000000000605ba2480000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007d00000000000000000000000000000000000000000000000008ac7230489e800000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000cb8c7409fe98a396f32d6cff4736bedc7b60008c000000000000000000000000000000000000000000000005f68e8131ecf800000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000605b005700000000000000000000000000000000000000000000000000000000605c51d70000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007d00000000000000000000000000000000000000000000000008ac7230489e80000000000000000000000000000000000000000000000000000000000000000000200000000000000000000000026caae548b7cecf98da12ccaaa633d6d140447aa00000000000000000000000000000000000000000000029d01c7829467b400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000605c4dac00000000000000000000000000000000000000000000000000000000605d9f2c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007d00000000000000000000000000000000000000000000000008ac7230489e80000"}
  end

  def query_response do
    [
      %{
        "createdAt" => "2021-03-23T20:34:16Z",
        "finishAt" => "2021-03-24T20:34:16Z",
        "fixedSheriffReward" => 10.0,
        "hunterAddress" => "0xcb8c7409fe98a396f32d6cff4736bedc7b60008c",
        "isRewardClaimed" => false,
        "proposalId" => "0",
        "reward" => 100.0,
        "sheriffsRewardShare" => 2.0e3,
        "state" => "DECLINED",
        "text" => nil,
        "title" => nil,
        "user" => nil,
        "votesAgainst" => 0.0,
        "votesFor" => 0.0,
        "hunterAddressLabels" => [],
        "proposedAddress" => nil,
        "proposedAddressLabels" => [],
        "userLabels" => nil
      },
      %{
        "createdAt" => "2021-03-24T09:03:19Z",
        "finishAt" => "2021-03-25T09:03:19Z",
        "fixedSheriffReward" => 10.0,
        "hunterAddress" => "0xcb8c7409fe98a396f32d6cff4736bedc7b60008c",
        "isRewardClaimed" => false,
        "proposalId" => "1",
        "reward" => 110.0,
        "sheriffsRewardShare" => 2.0e3,
        "state" => "DECLINED",
        "text" => nil,
        "title" => nil,
        "user" => nil,
        "votesAgainst" => 0.0,
        "votesFor" => 0.0,
        "hunterAddressLabels" => [],
        "proposedAddress" => nil,
        "proposedAddressLabels" => [],
        "userLabels" => nil
      },
      %{
        "createdAt" => "2021-03-25T08:45:32Z",
        "finishAt" => "2021-03-26T08:45:32Z",
        "fixedSheriffReward" => 10.0,
        "hunterAddress" => "0x26caae548b7cecf98da12ccaaa633d6d140447aa",
        "isRewardClaimed" => false,
        "proposalId" => "2",
        "reward" => 12341.0,
        "sheriffsRewardShare" => 2.0e3,
        "state" => "ACTIVE",
        "text" => "text",
        "title" => "title",
        "user" => %{"email" => "<email hidden>"},
        "votesAgainst" => 0.0,
        "votesFor" => 0.0,
        "hunterAddressLabels" => [%{"name" => "DEX Trader"}],
        "proposedAddress" => nil,
        "proposedAddressLabels" => [],
        "userLabels" => []
      }
    ]
  end
end
