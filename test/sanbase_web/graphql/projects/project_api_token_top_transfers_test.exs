defmodule SanbaseWeb.Graphql.ProjectApiTokenTopTransactionsTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  require Sanbase.Utils.Config

  setup do
    %{
      project: insert(:random_erc20_project),
      project_no_contract: insert(:random_erc20_project, contract_addresses: [])
    }
  end

  test "top token transactons for a project", %{conn: conn, project: project} do
    (&Sanbase.Transfers.Erc20Transfers.top_transfers/7)
    |> Sanbase.Mock.prepare_mock2(transfers())
    |> Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query/2, {:ok, %{rows: labels_rows()}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = project_by_slug_query(project)

      result = post(conn, "/graphql", query_skeleton(query, "projectBySlug"))

      assert json_response(result, 200)["data"]["projectBySlug"] == transactons_map()
    end)
  end

  test "project with no contract address returns empty string", %{
    conn: conn,
    project_no_contract: project_no_contract
  } do
    query = """
    {
      projectBySlug(
        slug: "#{project_no_contract.slug}") {
          tokenTopTransactions(
            from: "#{DateTime.from_naive!(~N[2018-06-10 10:33:47], "Etc/UTC")}",
            to: "#{DateTime.from_naive!(~N[2018-06-18 12:33:47], "Etc/UTC")}") {
              datetime
              trxHash
              trxValue
              fromAddress{ address }
              toAddress{ address }
          }
      }
    }
    """

    result = post(conn, "/graphql", query_skeleton(query, "projectBySlug"))

    assert json_response(result, 200)["data"]["projectBySlug"] == %{"tokenTopTransactions" => []}
  end

  test "cannot get top transfers by all projects query", %{conn: conn} do
    query = """
    {
      allErc20Projects{
        tokenTopTransactions(
          from: "#{DateTime.from_naive!(~N[2018-06-10 10:33:47], "Etc/UTC")}",
          to: "#{DateTime.from_naive!(~N[2018-06-18 12:33:47], "Etc/UTC")}"
        ) {
          datetime
          trxHash
          trxValue
          fromAddress{ address }
          toAddress{ address }
        }
      }
    }
    """

    result =
      conn
      |> post("/graphql", query_skeleton(query, "allErc20Projects"))
      |> json_response(200)

    assert result == %{
             "data" => %{"allErc20Projects" => nil},
             "errors" => [
               %{
                 "locations" => [%{"column" => 3, "line" => 2}],
                 "message" => "Cannot query [\"tokenTopTransactions\"] on a query that returns more than 1 project.",
                 "path" => ["allErc20Projects"]
               }
             ]
           }
  end

  # Private functions

  defp project_by_slug_query(project) do
    """
    {
      projectBySlug(
        slug: "#{project.slug}") {
        tokenTopTransactions(
          from: "#{DateTime.from_naive!(~N[2018-06-10 10:33:47], "Etc/UTC")}",
          to: "#{DateTime.from_naive!(~N[2018-06-18 12:33:47], "Etc/UTC")}"
        ) {
          datetime
          trxHash
          trxValue
          fromAddress{
            address
            labels {
              name
              metadata
            }
          }
          toAddress{
            address
            labels {
              name
              metadata
            }
          }
        }
      }
    }
    """
  end

  defp transfers do
    {:ok,
     [
       %{
         block_number: 5_619_729,
         contract: "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098",
         datetime: DateTime.from_naive!(~N[2018-06-10 10:33:47], "Etc/UTC"),
         from_address: "0xf4b51b14b9ee30dc37ec970b50a486f37686e2a8",
         log_index: 0,
         to_address: "0x742d35cc6634c0532925a3b844bc454e4438f44e",
         trx_hash: "0x9a561c88bb59a1f6dfe63ed4fe036466b3a328d1d86d039377481ab7c4defe4e",
         trx_value: 4.5,
         trx_position: 2
       },
       %{
         block_number: 5_769_021,
         contract: "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098",
         datetime: DateTime.from_naive!(~N[2018-06-10 12:33:47], "Etc/UTC"),
         from_address: "0x416eda5d6ed29cac3e6d97c102d61bc578c5db87",
         log_index: 2,
         to_address: "0xf9428b0e4959cb8d0e68d056a12dcd64ddef066e",
         trx_hash: "0xccbb803caabebd3665eec49673e23ef5cd08bd0be50a2b1f1506d77a523827ce",
         trx_value: 9.2,
         trx_position: 2
       },
       %{
         block_number: 5_770_231,
         contract: "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098",
         datetime: DateTime.from_naive!(~N[2018-06-11 12:33:47], "Etc/UTC"),
         from_address: "0xf9428b0e4959cb8d0e68d056a12dcd64ddef066e",
         log_index: 7,
         to_address: "0x876eabf441b2ee5b5b0554fd502a8e0600950cfa",
         trx_hash: "0x923f8054bf571ecd56db56f8aaf7b71b97f03ac7cf63e5cac929869cdbdd3863",
         trx_value: 9.2,
         trx_position: 2
       },
       %{
         block_number: 5_527_438,
         contract: "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098",
         datetime: DateTime.from_naive!(~N[2018-06-12 12:33:47], "Etc/UTC"),
         from_address: "0x17125b59ac51cee029e4bd78d7f5947d1ea49bb2",
         log_index: 56,
         to_address: "0x8f47cc86055f35ba939ff48e569105183fea64e8",
         trx_hash: "0xa891e1bbe292e546f40d23772b53a396ae2d37697665157bc6e019c647e9531a",
         trx_value: 2.5,
         trx_position: 2
       },
       %{
         block_number: 5_527_472,
         contract: "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098",
         datetime: DateTime.from_naive!(~N[2018-06-13 12:33:47], "Etc/UTC"),
         from_address: "0x8f47cc86055f35ba939ff48e569105183fea64e8",
         log_index: 62,
         to_address: "0x876eabf441b2ee5b5b0554fd502a8e0600950cfa",
         trx_hash: "0xd4341953103d0d850d3284910213482dae5f7677c929f768d72f121e5a556fb3",
         trx_value: 2.5,
         trx_position: 2
       },
       %{
         block_number: 5_569_693,
         contract: "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098",
         datetime: DateTime.from_naive!(~N[2018-06-14 12:33:47], "Etc/UTC"),
         from_address: "0x826d1ba25d5bf1485c755c8efecff3744f90d137",
         log_index: 4,
         to_address: "0x4976b5204c10a8de91cbc9224fb6d314454cf7d8",
         trx_hash: "0x398772430a2e39f5f1addfbba56b7db1e30e5417de52c15001e157e350c18e52",
         trx_value: 1.67,
         trx_position: 2
       },
       %{
         block_number: 5_569_715,
         contract: "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098",
         datetime: DateTime.from_naive!(~N[2018-06-15 12:33:47], "Etc/UTC"),
         from_address: "0x4976b5204c10a8de91cbc9224fb6d314454cf7d8",
         log_index: 7,
         to_address: "0x876eabf441b2ee5b5b0554fd502a8e0600950cfa",
         trx_hash: "0x31a5d24e2fa078b88b49bd1180f6b29dfe145bb51b6f98543fe9bccf6e15bba2",
         trx_value: 1.67,
         trx_position: 2
       },
       %{
         block_number: 5_527_047,
         contract: "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098",
         datetime: DateTime.from_naive!(~N[2018-06-16 12:33:47], "Etc/UTC"),
         from_address: "0x17125b59ac51cee029e4bd78d7f5947d1ea49bb2",
         log_index: 58,
         to_address: "0x0bd1b5cc4c63f99d00f4a3c5cad3619070c5c1c3",
         trx_hash: "0xa99da23a274c33d40d950fbc03bee7330e518ef6a9622ddd818cb9b967f9f520",
         trx_value: 1.0,
         trx_position: 2
       },
       %{
         block_number: 5_528_483,
         contract: "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098",
         datetime: DateTime.from_naive!(~N[2018-06-17 12:33:47], "Etc/UTC"),
         from_address: "0x0bd1b5cc4c63f99d00f4a3c5cad3619070c5c1c3",
         log_index: 53,
         to_address: "0x5e575279bf9f4acf0a130c186861454247394c06",
         trx_hash: "0x2110456180d0990d1f58c375faab828bb85abc16fe5e56264e84f32864708f3b",
         trx_value: 1.0,
         trx_position: 2
       },
       %{
         block_number: 5_812_594,
         contract: "0x7c5a0ce9267ed19b22f8cae653f198e3e8daf098",
         datetime: DateTime.from_naive!(~N[2018-06-18 12:33:47], "Etc/UTC"),
         from_address: "0x1f3df0b8390bb8e9e322972c5e75583e87608ec2",
         log_index: 14,
         to_address: "0x157dd308abb91ed2cd5a770bc1cf0fd458c7498c",
         trx_hash: "0x77ffc9c2ff1678d3f536357eb6e2a032981c98c46e541266ef152752f159187d",
         trx_value: 8.3,
         trx_position: 2
       }
     ]}
  end

  defp labels_rows do
    [
      [
        "0xf4b51b14b9ee30dc37ec970b50a486f37686e2a8",
        "centralized_exchange",
        ~s|{"comment":"Poloniex GNT","is_dex":false,"owner":"Poloniex","source":""}|
      ],
      [
        "0xf4b51b14b9ee30dc37ec970b50a486f37686e2a8",
        "whale",
        ~s|{"rank": 58, "value": 1.1438690681177702e+24}|
      ]
    ]
  end

  defp transactons_map do
    %{
      "tokenTopTransactions" => [
        %{
          "datetime" => "2018-06-10T10:33:47Z",
          "fromAddress" => %{
            "address" => "0xf4b51b14b9ee30dc37ec970b50a486f37686e2a8",
            "labels" => [
              %{
                "name" => "centralized_exchange",
                "metadata" => ~s|{"comment":"Poloniex GNT","is_dex":false,"owner":"Poloniex","source":""}|
              },
              %{
                "name" => "whale",
                "metadata" => ~s|{"rank": 58, "value": 1.1438690681177702e+24}|
              }
            ]
          },
          "toAddress" => %{
            "address" => "0x742d35cc6634c0532925a3b844bc454e4438f44e",
            "labels" => []
          },
          "trxHash" => "0x9a561c88bb59a1f6dfe63ed4fe036466b3a328d1d86d039377481ab7c4defe4e",
          "trxValue" => 4.5
        },
        %{
          "datetime" => "2018-06-10T12:33:47Z",
          "fromAddress" => %{
            "address" => "0x416eda5d6ed29cac3e6d97c102d61bc578c5db87",
            "labels" => []
          },
          "toAddress" => %{
            "address" => "0xf9428b0e4959cb8d0e68d056a12dcd64ddef066e",
            "labels" => []
          },
          "trxHash" => "0xccbb803caabebd3665eec49673e23ef5cd08bd0be50a2b1f1506d77a523827ce",
          "trxValue" => 9.2
        },
        %{
          "datetime" => "2018-06-11T12:33:47Z",
          "fromAddress" => %{
            "address" => "0xf9428b0e4959cb8d0e68d056a12dcd64ddef066e",
            "labels" => []
          },
          "toAddress" => %{
            "address" => "0x876eabf441b2ee5b5b0554fd502a8e0600950cfa",
            "labels" => []
          },
          "trxHash" => "0x923f8054bf571ecd56db56f8aaf7b71b97f03ac7cf63e5cac929869cdbdd3863",
          "trxValue" => 9.2
        },
        %{
          "datetime" => "2018-06-12T12:33:47Z",
          "fromAddress" => %{
            "address" => "0x17125b59ac51cee029e4bd78d7f5947d1ea49bb2",
            "labels" => []
          },
          "toAddress" => %{
            "address" => "0x8f47cc86055f35ba939ff48e569105183fea64e8",
            "labels" => []
          },
          "trxHash" => "0xa891e1bbe292e546f40d23772b53a396ae2d37697665157bc6e019c647e9531a",
          "trxValue" => 2.5
        },
        %{
          "datetime" => "2018-06-13T12:33:47Z",
          "fromAddress" => %{
            "address" => "0x8f47cc86055f35ba939ff48e569105183fea64e8",
            "labels" => []
          },
          "toAddress" => %{
            "address" => "0x876eabf441b2ee5b5b0554fd502a8e0600950cfa",
            "labels" => []
          },
          "trxHash" => "0xd4341953103d0d850d3284910213482dae5f7677c929f768d72f121e5a556fb3",
          "trxValue" => 2.5
        },
        %{
          "datetime" => "2018-06-14T12:33:47Z",
          "fromAddress" => %{
            "address" => "0x826d1ba25d5bf1485c755c8efecff3744f90d137",
            "labels" => []
          },
          "toAddress" => %{
            "address" => "0x4976b5204c10a8de91cbc9224fb6d314454cf7d8",
            "labels" => []
          },
          "trxHash" => "0x398772430a2e39f5f1addfbba56b7db1e30e5417de52c15001e157e350c18e52",
          "trxValue" => 1.67
        },
        %{
          "datetime" => "2018-06-15T12:33:47Z",
          "fromAddress" => %{
            "address" => "0x4976b5204c10a8de91cbc9224fb6d314454cf7d8",
            "labels" => []
          },
          "toAddress" => %{
            "address" => "0x876eabf441b2ee5b5b0554fd502a8e0600950cfa",
            "labels" => []
          },
          "trxHash" => "0x31a5d24e2fa078b88b49bd1180f6b29dfe145bb51b6f98543fe9bccf6e15bba2",
          "trxValue" => 1.67
        },
        %{
          "datetime" => "2018-06-16T12:33:47Z",
          "fromAddress" => %{
            "address" => "0x17125b59ac51cee029e4bd78d7f5947d1ea49bb2",
            "labels" => []
          },
          "toAddress" => %{
            "address" => "0x0bd1b5cc4c63f99d00f4a3c5cad3619070c5c1c3",
            "labels" => []
          },
          "trxHash" => "0xa99da23a274c33d40d950fbc03bee7330e518ef6a9622ddd818cb9b967f9f520",
          "trxValue" => 1.0
        },
        %{
          "datetime" => "2018-06-17T12:33:47Z",
          "fromAddress" => %{
            "address" => "0x0bd1b5cc4c63f99d00f4a3c5cad3619070c5c1c3",
            "labels" => []
          },
          "toAddress" => %{
            "address" => "0x5e575279bf9f4acf0a130c186861454247394c06",
            "labels" => []
          },
          "trxHash" => "0x2110456180d0990d1f58c375faab828bb85abc16fe5e56264e84f32864708f3b",
          "trxValue" => 1.0
        },
        %{
          "datetime" => "2018-06-18T12:33:47Z",
          "fromAddress" => %{
            "address" => "0x1f3df0b8390bb8e9e322972c5e75583e87608ec2",
            "labels" => []
          },
          "toAddress" => %{
            "address" => "0x157dd308abb91ed2cd5a770bc1cf0fd458c7498c",
            "labels" => []
          },
          "trxHash" => "0x77ffc9c2ff1678d3f536357eb6e2a032981c98c46e541266ef152752f159187d",
          "trxValue" => 8.3
        }
      ]
    }
  end
end
