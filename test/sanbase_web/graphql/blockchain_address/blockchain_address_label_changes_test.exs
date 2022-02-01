defmodule SanbaseWeb.Graphql.BlockchainAddressLabelChangesApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)
    eth_infrastructure = insert(:infrastructure, code: "ETH")

    %{
      user: user,
      conn: conn,
      anon_conn: build_conn(),
      eth_infrastructure: eth_infrastructure
    }
  end

  test "get label changes", context do
    label_changes_rows = [
      [1_499_172_741, "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098", "santiment/contract:v1", 1],
      [1_509_172_741, "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098", "santiment/whale:v1", 1],
      [1_559_172_741, "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098", "santiment/whale:v1", -1]
    ]

    label_rows = [
      [
        "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098",
        "centralized_exchange",
        ~s|{"comment":"Poloniex GNT","is_dex":false,"owner":"Poloniex","source":""}|
      ]
    ]

    # First mock the labels_change call then mock the add_labels call
    mock_fun =
      Sanbase.Mock.wrap_consecutives(
        [
          fn -> {:ok, %{rows: label_changes_rows}} end,
          fn -> {:ok, %{rows: label_rows}} end
        ],
        arity: 2
      )

    Sanbase.Mock.prepare_mock(Sanbase.ClickhouseRepo, :query, mock_fun)
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        blockchain_address_label_changes(
          context.conn,
          %{address: "0x123", infrastructure: "ETH"},
          ~U[2015-01-01 00:00:00Z],
          ~U[2021-05-01 00:00:00Z]
        )
        |> get_in(["data", "blockchainAddressLabelChanges"])

      assert result == [
               %{
                 "address" => %{
                   "address" => "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098",
                   "currentUserAddressDetails" => nil,
                   "infrastructure" => "ETH"
                 },
                 "datetime" => "2017-07-04T12:52:21Z",
                 "label" => "santiment/contract:v1",
                 "sign" => 1
               },
               %{
                 "address" => %{
                   "address" => "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098",
                   "currentUserAddressDetails" => nil,
                   "infrastructure" => "ETH"
                 },
                 "datetime" => "2017-10-28T06:39:01Z",
                 "label" => "santiment/whale:v1",
                 "sign" => 1
               },
               %{
                 "address" => %{
                   "address" => "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098",
                   "currentUserAddressDetails" => nil,
                   "infrastructure" => "ETH"
                 },
                 "datetime" => "2019-05-29T23:32:21Z",
                 "label" => "santiment/whale:v1",
                 "sign" => -1
               }
             ]
    end)
  end

  defp blockchain_address_label_changes(conn, selector, from, to) do
    query = """
    {
      blockchainAddressLabelChanges(selector: #{map_to_input_object_str(selector)} from: "#{from}" to: "#{to}") {
       datetime
       sign
       label
       address {
         address
         infrastructure
         currentUserAddressDetails {
           labels {
             metadata
             name
             origin
           }
           watchlists {
             id
             slug
           }
         }
       }
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query))
    |> json_response(200)
  end
end
