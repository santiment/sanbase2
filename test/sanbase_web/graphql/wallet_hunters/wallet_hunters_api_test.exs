defmodule SanbaseWeb.Graphql.WalletHuntersApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers
  alias Sanbase.WalletHunters.{RelayQuota, RelayerApi, Contract}

  setup do
    user = insert(:user)

    proposal =
      insert(:wallet_hunters_proposal,
        proposal_id: 2,
        user: user,
        hunter_address: "0x26caae548b7cecf98da12ccaaa633d6d140447aa",
        transaction_id: "0x2"
      )

    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user, proposal: proposal}
  end

  describe "Create proposal" do
    setup do
      create_args = %{
        text: "t1",
        title: "t2",
        hunter_address: "0xcb8c7409fe98a396f32d6cff4736bedc7b60008c",
        proposed_address: "0xcb8c7409fe98a396f32d6cff4736bedc7b60008c",
        request: %{
          data: "0x2c62c181000000000000000000000000301addd55603a559fe0af598eeee4cd3564f7355",
          from: "0x301addd55603a559fe0af598eeee4cd3564f7355",
          gas: 0,
          nonce: "0",
          to: "0x244d7B189CB0fc5fff6cb22893862aE581e0dbC3",
          value: 0
        },
        signature:
          "0xe49d1f4cc653a6a3ce249ab2a4bebfe542f10e31d17a38afd1037cb07068340e61d50cd0d0b412ad28f11a02e2361d2fe3fb996bdb0e78b584e26683813322461b"
      }

      create_without_relay_args = %{
        text: "t1",
        title: "t2",
        hunter_address: "0xcb8c7409fe98a396f32d6cff4736bedc7b60008c",
        proposed_address: "0xcb8c7409fe98a396f32d6cff4736bedc7b60008c",
        transaction_id: "0x1"
      }

      {:ok,
       create_args: create_args,
       create_without_relay_args: create_without_relay_args,
       transaction_id: "0x1"}
    end

    test "with relay when everything is ok", context do
      args = context.create_args

      Sanbase.Mock.prepare_mock2(&RelayQuota.can_relay?/1, true)
      |> Sanbase.Mock.prepare_mock2(
        &RelayerApi.relay/2,
        {:ok, %{"hash" => context.transaction_id}}
      )
      |> Sanbase.Mock.prepare_mock2(&RelayQuota.create_or_update/1, {:ok, %{}})
      |> Sanbase.Mock.prepare_mock2(
        &Sanbase.ClickhouseRepo.query/2,
        {:ok, %{rows: labels_rows()}}
      )
      |> Sanbase.Mock.prepare_mock2(&Contract.get_trx_by_id/1, {:ok, %{"blockNumber" => "0x1"}})
      |> Sanbase.Mock.prepare_mock2(&Contract.get_trx_receipt_by_id/1, {:ok, %{"logs" => []}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        result =
          execute_mutation(context.conn, create_proposal_mutation(args), "createWhProposal")

        assert result == %{
                 "hunterAddress" => args.hunter_address,
                 "proposalId" => nil,
                 "proposedAddress" => args.proposed_address,
                 "text" => args.text,
                 "title" => args.title,
                 "transactionId" => context.transaction_id,
                 "transactionStatus" => "pending",
                 "user" => %{"email" => context.user.email}
               }
      end)
    end

    test "without relay when everything is ok", context do
      args = context.create_without_relay_args

      Sanbase.Mock.prepare_mock2(
        &Sanbase.ClickhouseRepo.query/2,
        {:ok, %{rows: labels_rows()}}
      )
      |> Sanbase.Mock.prepare_mock2(&Contract.get_trx_by_id/1, {:ok, %{"blockNumber" => "0x1"}})
      |> Sanbase.Mock.prepare_mock2(&Contract.get_trx_receipt_by_id/1, {:ok, %{"logs" => []}})
      |> Sanbase.Mock.run_with_mocks(fn ->
        result =
          execute_mutation(
            context.conn,
            create_proposal_withut_relay_mutation(args),
            "createWhProposal"
          )

        assert result == %{
                 "hunterAddress" => args.hunter_address,
                 "proposalId" => nil,
                 "proposedAddress" => args.proposed_address,
                 "text" => args.text,
                 "title" => args.title,
                 "transactionId" => context.transaction_id,
                 "transactionStatus" => "pending",
                 "user" => %{"email" => context.user.email}
               }
      end)
    end
  end

  describe "Fetch proposals" do
    setup do
      insert(:wallet_hunters_proposal, proposal_id: 0, transaction_id: "0x0")
      insert(:wallet_hunters_proposal, proposal_id: 1, transaction_id: "0x1")

      mock_fun =
        [
          fn -> {:ok, "0x0000000000000000000000000000000000000000000000000000000000000003"} end,
          fn -> all_proposals_resp() end
        ]
        |> Sanbase.Mock.wrap_consecutives(arity: 1)

      global_mock =
        Sanbase.Mock.prepare_mock(Ethereumex.HttpClient, :eth_call, mock_fun)
        |> Sanbase.Mock.prepare_mock2(&Ethereumex.HttpClient.eth_get_logs/1, votes_resp())
        |> Sanbase.Mock.prepare_mock2(
          &Sanbase.ClickhouseRepo.query/2,
          {:ok, %{rows: labels_rows()}}
        )

      {:ok, global_mock: global_mock}
    end

    test "when fetching all", context do
      context.global_mock
      |> Sanbase.Mock.run_with_mocks(fn ->
        result = execute_query(build_conn(), wallet_hunters_query(), "walletHuntersProposals")

        assert result == query_response()
      end)
    end

    test "when fetching with sorting and pagination", context do
      context.global_mock
      |> Sanbase.Mock.run_with_mocks(fn ->
        selector = %{sort_by: %{field: "created_at", direction: :desc}, page: 1, page_size: 2}

        result =
          execute_query(build_conn(), wallet_hunters_query(selector), "walletHuntersProposals")

        assert result ==
                 query_response() |> Enum.sort_by(& &1["createdAt"], :desc) |> Enum.take(2)
      end)
    end

    test "when fetching with filter", context do
      context.global_mock
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

    test "when fetching only mine", context do
      context.global_mock
      |> Sanbase.Mock.run_with_mocks(fn ->
        selector = %{type: :only_mine}

        result =
          execute_query(context.conn, wallet_hunters_query(selector), "walletHuntersProposals")

        expected =
          query_response()
          |> List.last()
          |> Map.merge(%{"user" => %{"email" => context.user.email}})

        assert hd(result) == expected
      end)
    end

    test "when fetching only voted", context do
      user =
        insert(:user,
          eth_accounts: [
            %Sanbase.Accounts.EthAccount{address: "0x9a70009b09d729453333121a7d47bd9a039b9153"}
          ]
        )

      conn = setup_jwt_auth(build_conn(), user)

      context.global_mock
      |> Sanbase.Mock.run_with_mocks(fn ->
        selector = %{type: :only_voted}

        result = execute_query(conn, wallet_hunters_query(selector), "walletHuntersProposals")

        expected = query_response() |> hd()

        assert hd(result) == expected
      end)
    end
  end

  defp create_proposal_mutation(args) do
    """
    mutation {
      createWhProposal(
        text: "#{args.text}",
        title:"#{args.title}",
        hunterAddress:"0xcb8c7409fe98a396f32d6cff4736bedc7b60008c",
        proposedAddress:"0xcb8c7409fe98a396f32d6cff4736bedc7b60008c",
        request: #{map_to_input_object_str(args.request, map_as_input_object: false)},
        signature: "#{args.signature}"
      ) {
        proposalId
        user {
          email
        }
        title
        text
        hunterAddress
        proposedAddress
        transactionId
        transactionStatus
      }
    }
    """
  end

  defp create_proposal_withut_relay_mutation(args) do
    """
    mutation {
      createWhProposal(
        text: "#{args.text}",
        title:"#{args.title}",
        hunterAddress:"0xcb8c7409fe98a396f32d6cff4736bedc7b60008c",
        proposedAddress:"0xcb8c7409fe98a396f32d6cff4736bedc7b60008c",
        transactionId: "#{args.transaction_id}"
      ) {
        proposalId
        user {
          email
        }
        title
        text
        hunterAddress
        proposedAddress
        transactionId
        transactionStatus
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
        votes {
          amount
          voterAddress
          votedFor
        }
        votesCount
        transactionId
        transactionStatus
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

  defp all_proposals_resp do
    {:ok,
     "0x000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cb8c7409fe98a396f32d6cff4736bedc7b60008c0000000000000000000000000000000000000000000000056bc75e2d631000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000605a50c800000000000000000000000000000000000000000000000000000000605ba2480000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007d00000000000000000000000000000000000000000000000008ac7230489e800000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000cb8c7409fe98a396f32d6cff4736bedc7b60008c000000000000000000000000000000000000000000000005f68e8131ecf800000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000605b005700000000000000000000000000000000000000000000000000000000605c51d70000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007d00000000000000000000000000000000000000000000000008ac7230489e80000000000000000000000000000000000000000000000000000000000000000000200000000000000000000000026caae548b7cecf98da12ccaaa633d6d140447aa00000000000000000000000000000000000000000000029d01c7829467b400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000605c4dac00000000000000000000000000000000000000000000000000000000605d9f2c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007d00000000000000000000000000000000000000000000000008ac7230489e80000"}
  end

  def votes_resp do
    {:ok,
     [
       %{
         "address" => "0x772e255402eee3fa243cb17af58001f40da78d90",
         "blockHash" => "0x72efb342bec68dabb61e5b749a2374760b44b086d44a7efa25fba52a75b1f8eb",
         "blockNumber" => "0x7f1bd3",
         "data" =>
           "0x000000000000000000000000000000000000000000000002b5e3af16b18800000000000000000000000000000000000000000000000000000000000000000001",
         "logIndex" => "0x5",
         "removed" => false,
         "topics" => [
           "0xb7086a9dd618ffa688aa9500720dfe31d3b288daba445664cecceaed4a1562c3",
           "0x0000000000000000000000000000000000000000000000000000000000000000",
           "0x0000000000000000000000009a70009b09d729453333121a7d47bd9a039b9153"
         ],
         "transactionHash" =>
           "0x94ea7542946b1e4e64f7f7f398221fb2fa3eff67dc68cdb8f20fb9250611460f",
         "transactionIndex" => "0x4"
       }
     ]}
  end

  defp query_response do
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
        "userLabels" => [],
        "votes" => [
          %{
            "amount" => 50.0,
            "votedFor" => true,
            "voterAddress" => "0x9a70009b09d729453333121a7d47bd9a039b9153"
          }
        ],
        "votesCount" => 1,
        "transactionId" => "0x0",
        "transactionStatus" => "pending"
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
        "userLabels" => [],
        "votes" => [],
        "votesCount" => 0,
        "transactionId" => "0x1",
        "transactionStatus" => "pending"
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
        "text" => nil,
        "title" => nil,
        "user" => %{"email" => "<email hidden>"},
        "votesAgainst" => 0.0,
        "votesFor" => 0.0,
        "hunterAddressLabels" => [%{"name" => "DEX Trader"}],
        "proposedAddress" => nil,
        "proposedAddressLabels" => [],
        "userLabels" => [],
        "votes" => [],
        "votesCount" => 0,
        "transactionId" => "0x2",
        "transactionStatus" => "pending"
      }
    ]
  end
end
