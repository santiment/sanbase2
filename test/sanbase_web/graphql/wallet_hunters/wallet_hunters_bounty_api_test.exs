defmodule SanbaseWeb.Graphql.WalletHuntersBountyApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)

    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  describe "Create bounty" do
    setup do
      create_args = %{
        description: "t1",
        title: "t2",
        duration: "1w",
        proposals_count: 1,
        proposal_reward: 300,
        transaction_id: "0x1"
      }

      {:ok, create_args: create_args, transaction_id: "0x1"}
    end

    test "everything is ok", context do
      result = execute_mutation(context.conn, create_bounty_mutation(), "createWhBounty")

      assert result == %{
               "id" => result["id"],
               "description" => "t1",
               "duration" => "1w",
               "proposalReward" => 300,
               "proposalsCount" => 1,
               "title" => "t2",
               "transactionId" => "0x1",
               "user" => %{"email" => context.user.email}
             }

      result =
        execute_query(build_conn(), wallet_hunters_bounties_query(), "walletHuntersBounties")

      id = result |> hd() |> Map.get("id")

      assert result == [
               %{
                 "id" => id,
                 "description" => "t1",
                 "duration" => "1w",
                 "proposalReward" => 300,
                 "proposalsCount" => 1,
                 "title" => "t2",
                 "transactionId" => "0x1",
                 "transactionStatus" => "pending",
                 "user" => %{"email" => "<email hidden>"}
               }
             ]

      result = execute_query(build_conn(), wallet_hunters_bounty_query(id), "walletHuntersBounty")

      assert result == %{
               "description" => "t1",
               "duration" => "1w",
               "proposalReward" => 300,
               "proposalsCount" => 1,
               "title" => "t2",
               "transactionId" => "0x1",
               "transactionStatus" => "pending",
               "user" => %{"email" => "<email hidden>"}
             }
    end
  end

  describe "Fetch bounties" do
    test "when fetching all", _context do
      result =
        execute_query(build_conn(), wallet_hunters_bounties_query(), "walletHuntersBounties")

      assert result == []
    end
  end

  defp create_bounty_mutation() do
    """
    mutation {
      createWhBounty(
        description: "t1",
        title: "t2",
        duration: "1w"
        proposals_count: 1,
        proposal_reward: 300,
        transaction_id: "0x1"
      ) {
        id
        user {
          email
        }
        title
        description
        duration
        proposalsCount
        proposalReward
        transactionId
      }
    }
    """
  end

  defp wallet_hunters_bounties_query() do
    """
    {
      walletHuntersBounties {
        id
        user {
          email
        }
        title
        description
        duration
        proposalsCount
        proposalReward
        transactionId
        transactionStatus
      }
    }
    """
  end

  defp wallet_hunters_bounty_query(id) do
    """
    {
      walletHuntersBounty(id: #{id}) {
        user {
          email
        }
        title
        description
        duration
        proposalsCount
        proposalReward
        transactionId
        transactionStatus
      }
    }
    """
  end
end
