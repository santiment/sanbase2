defmodule SanbaseWeb.Graphql.NftTradesApiTest do
  use SanbaseWeb.ConnCase, async: true

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  test "get nft trades", %{conn: conn} do
    project = insert(:random_erc20_project)

    rows = [
      [
        1_638_339_408,
        18.3,
        [1.0],
        project.slug,
        "0xa497bf3e9ea849361fc78fc405861abf97ed08addb5ca4e3da688331ffa38344",
        "0xd387a6e4e84a6c86bd90c158c6028a58cc8ac459",
        "0xa88ae2c098a3ad39184a4d64c6ddb39a237531b2",
        "0xa1d4657e0e6507d5a94d06da93e94dc7c8c44b51",
        "nft contract name",
        "opensea",
        ["buy"]
      ],
      [
        1_637_831_576,
        16.4,
        [2.0],
        project.slug,
        "0xc98a6ed5c0a139d7437d96d67e120f0ba568915daeb46182bdb27ad37367c0c8",
        "0x694cd849bc80f3f772ab9aef4be2df3af054dc6b",
        "0x721931508df2764fd4f70c53da646cb8aed16ace",
        "0xad9fd7cb4fc7a0fbce08d64068f60cbde22ed34c",
        "nft contract name2",
        "opensea",
        ["sell"]
      ]
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      from = ~U[2021-11-01 00:00:00Z]
      to = ~U[2021-12-15 00:00:00Z]

      # Because of the mock both results will be equal. This tests that both
      # order by keys are accepted
      result_order_by_amount = get_nft_influencer_trades(conn, from, to, 1, 10, :amount, :asc)
      result_order_by_dt = get_nft_influencer_trades(conn, from, to, 1, 10, :datetime, :desc)

      assert result_order_by_amount == result_order_by_dt

      assert result_order_by_amount == [
               %{
                 "amount" => 18.3,
                 "quantity" => 1.0,
                 "datetime" => "2021-12-01T06:16:48Z",
                 "fromAddress" => %{
                   "address" => "0xa88ae2c098a3ad39184a4d64c6ddb39a237531b2",
                   "labelKey" => nil
                 },
                 "marketplace" => "opensea",
                 "nft" => %{
                   "name" => "nft contract name",
                   "contractAddress" => "0xa1d4657e0e6507d5a94d06da93e94dc7c8c44b51"
                 },
                 "currencyProject" => %{"slug" => project.slug},
                 "toAddress" => %{
                   "address" => "0xd387a6e4e84a6c86bd90c158c6028a58cc8ac459",
                   "labelKey" => "NFT_INFLUENCER"
                 },
                 "trxHash" => "0xa497bf3e9ea849361fc78fc405861abf97ed08addb5ca4e3da688331ffa38344",
                 "priceUsd" => 18.3
               },
               %{
                 "amount" => 16.4,
                 "quantity" => 2.0,
                 "datetime" => "2021-11-25T09:12:56Z",
                 "fromAddress" => %{
                   "address" => "0x721931508df2764fd4f70c53da646cb8aed16ace",
                   "labelKey" => "NFT_INFLUENCER"
                 },
                 "marketplace" => "opensea",
                 "nft" => %{
                   "name" => "nft contract name2",
                   "contractAddress" => "0xad9fd7cb4fc7a0fbce08d64068f60cbde22ed34c"
                 },
                 "currencyProject" => %{"slug" => project.slug},
                 "toAddress" => %{
                   "address" => "0x694cd849bc80f3f772ab9aef4be2df3af054dc6b",
                   "labelKey" => nil
                 },
                 "trxHash" => "0xc98a6ed5c0a139d7437d96d67e120f0ba568915daeb46182bdb27ad37367c0c8",
                 "priceUsd": 16.4
               }
             ]
    end)
  end

  defp get_nft_influencer_trades(conn, from, to, page, page_size, order_by, direction) do
    query = """
    {
    getNftTrades(
      LABEL_KEY: NFT_INFLUENCER
      from: "#{from}"
      to: "#{to}"
      page: #{page}
      pageSize: #{page_size}
      order_by: #{order_by |> Atom.to_string() |> String.upcase()}
      direction: #{direction |> Atom.to_string() |> String.upcase()}){
        datetime
        fromAddress { address labelKey }
        toAddress { address labelKey }
        nft { name contractAddress }
        trxHash
        marketplace
        currencyProject { slug }
        amount
        quantity
        priceUsd
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
    |> get_in(["data", "getNftTrades"])
  end
end
