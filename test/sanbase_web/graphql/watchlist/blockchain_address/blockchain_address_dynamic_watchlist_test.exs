defmodule SanbaseWeb.Graphql.BlockchainAddressDynamicWatchlistTest do
  use SanbaseWeb.ConnCase, async: false

  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.Factory

  setup do
    user = insert(:user)

    insert(:infrastructure, %{code: "ETH"})
    conn = setup_jwt_auth(build_conn(), user)

    %{conn: conn, user: user}
  end

  test "wrongly configured function fails on create", %{conn: conn} do
    function = %{
      "name" => "address_selector",
      "args" => %{
        # mistyped
        "filterss" => [
          %{
            "name" => "top_addresses",
            "args" => %{
              "slug" => "ethereum",
              "page" => 1,
              "page_size" => 2,
              "labels" => ["centralized_exchange", "decentralized_exchange", "CEX Trader"]
            }
          }
        ]
      }
    }

    error =
      do_execute_mutation(conn, create_watchlist_query(function: function))
      |> Map.get("errors")
      |> hd()

    assert %{
             "details" => %{
               "function" => [
                 "Provided watchlist function is not valid. Reason: Dynamic watchlist 'address_selector' has unsupported fields: [\"filterss\"]"
               ]
             },
             "message" => "Cannot create user list"
           } = error
  end

  test "wrongly configured function fails on update", %{conn: conn, user: user} do
    watchlist = insert(:watchlist, user: user)

    function = %{
      "name" => "address_selector",
      "args" => %{
        # mistyped
        "filterss" => [
          %{
            "name" => "top_addresses",
            "args" => %{
              "slug" => "ethereum",
              "page" => 1,
              "page_size" => 2,
              "labels" => ["centralized_exchange", "decentralized_exchange", "CEX Trader"]
            }
          }
        ]
      }
    }

    error =
      do_execute_mutation(
        conn,
        update_watchlist_query(id: watchlist.id, function: function)
      )
      |> Map.get("errors")
      |> hd()

    assert %{
             "details" => %{
               "function" => [
                 "Provided watchlist function is not valid. Reason: Dynamic watchlist 'address_selector' has unsupported fields: [\"filterss\"]"
               ]
             },
             "message" => "Cannot update user list"
           } = error
  end

  describe "top_addresses blockchain address selector" do
    test "dynamic watchlist for selector", %{conn: conn, user: user} do
      # Have at least 1 project that is not included in the result
      insert(:random_erc20_project)

      function = %{
        "name" => "address_selector",
        "args" => %{
          "filters" => [
            %{
              "name" => "top_addresses",
              "args" => %{
                "slug" => "ethereum",
                "page" => 1,
                "page_size" => 2,
                "labels" => ["centralized_exchange", "decentralized_exchange", "CEX Trader"]
              }
            }
          ]
        }
      }

      top_addresses_result = Enum.slice(top_addresses_result(), 0, 2)

      Sanbase.Mock.prepare_mock2(
        &Sanbase.Balance.current_balance_top_addresses/2,
        {:ok, top_addresses_result}
      )
      |> Sanbase.Mock.prepare_mock2(
        &Sanbase.Clickhouse.Label.get_address_labels/2,
        {:ok, labels_result()}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        result = do_execute_mutation(conn, create_watchlist_query(function: function))

        user_list = result["data"]["createWatchlist"]

        assert user_list["name"] == "My list"
        assert user_list["type"] == "BLOCKCHAIN_ADDRESS"
        assert user_list["color"] == "BLACK"
        assert user_list["isPublic"] == false
        assert user_list["user"]["id"] == user.id |> to_string()

        assert length(user_list["listItems"]) == 2

        assert %{
                 "blockchainAddress" => %{
                   "address" => "0x4269cba223b56458d72bdce36afbe48996d78f24",
                   "infrastructure" => "ETH",
                   "labels" => [
                     %{"name" => "CEX Trader", "origin" => "santiment"}
                   ]
                 }
               } in user_list["listItems"]

        assert %{
                 "blockchainAddress" => %{
                   "address" => "0xa5409ec958c83c3f309868babaca7c86dcb077c1",
                   "infrastructure" => "ETH",
                   "labels" => [
                     %{"name" => "CEX Trader", "origin" => "santiment"}
                   ]
                 }
               } in user_list["listItems"]
      end)
    end

    test "dynamic watchlist for selector with filtersCombinator OR", context do
      %{conn: conn, user: user} = context
      # Have at least 1 project that is not included in the result
      insert(:random_erc20_project)

      function = %{
        "name" => "address_selector",
        "args" => %{
          "filters_combinator" => "or",
          "filters" => [
            %{
              "name" => "top_addresses",
              "args" => %{
                "slug" => "ethereum",
                "page" => 1,
                "page_size" => 2
              }
            },
            %{
              "name" => "top_addresses",
              "args" => %{
                "slug" => "santiment",
                "page" => 1,
                "page_size" => 2
              }
            }
          ]
        }
      }

      mock_fun =
        [
          fn -> {:ok, Enum.slice(top_addresses_result(), 0, 2)} end,
          fn -> {:ok, Enum.slice(top_addresses_result(), 2, 2)} end
        ]
        |> Sanbase.Mock.wrap_consecutives(arity: 2)

      Sanbase.Mock.prepare_mock(
        Sanbase.Balance,
        :current_balance_top_addresses,
        mock_fun
      )
      |> Sanbase.Mock.prepare_mock2(
        &Sanbase.Clickhouse.Label.get_address_labels/2,
        {:ok, labels_result()}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        result = do_execute_mutation(conn, create_watchlist_query(function: function))

        user_list = result["data"]["createWatchlist"]

        assert user_list["name"] == "My list"
        assert user_list["type"] == "BLOCKCHAIN_ADDRESS"
        assert user_list["color"] == "BLACK"
        assert user_list["isPublic"] == false
        assert user_list["user"]["id"] == user.id |> to_string()

        assert length(user_list["listItems"]) == 4

        assert %{
                 "blockchainAddress" => %{
                   "address" => "0x4269cba223b56458d72bdce36afbe48996d78f24",
                   "infrastructure" => "ETH",
                   "labels" => [%{"name" => "CEX Trader", "origin" => "santiment"}]
                 }
               } in user_list["listItems"]

        assert %{
                 "blockchainAddress" => %{
                   "address" => "0x7125160a07a753b988839b004673c668012dd631",
                   "infrastructure" => "ETH",
                   "labels" => [%{"name" => "CEX Trader", "origin" => "santiment"}]
                 }
               } in user_list["listItems"]

        assert %{
                 "blockchainAddress" => %{
                   "address" => "0xa5409ec958c83c3f309868babaca7c86dcb077c1",
                   "infrastructure" => "ETH",
                   "labels" => [%{"name" => "CEX Trader", "origin" => "santiment"}]
                 }
               } in user_list["listItems"]

        assert %{
                 "blockchainAddress" => %{
                   "address" => "0xeb2629a2734e272bcc07bda959863f316f4bd4cf",
                   "infrastructure" => "ETH",
                   "labels" => [%{"name" => "CEX Trader", "origin" => "santiment"}]
                 }
               } in user_list["listItems"]
      end)
    end

    test "dynamic watchlist for selector with filtersCombinator AND", context do
      %{conn: conn, user: user} = context
      # Have at least 1 project that is not included in the result
      insert(:random_erc20_project)

      function = %{
        "name" => "address_selector",
        "args" => %{
          "filters_combinator" => "and",
          "filters" => [
            %{
              "name" => "top_addresses",
              "args" => %{
                "slug" => "ethereum",
                "page" => 1,
                "page_size" => 1,
                "threshold" => 2
              }
            },
            %{
              "name" => "top_addresses",
              "args" => %{
                "slug" => "santiment",
                "page" => 1,
                "page_size" => 1,
                "threshold" => 2
              }
            }
          ]
        }
      }

      mock_fun =
        [
          fn -> {:ok, Enum.slice(top_addresses_result(), 0, 2)} end,
          fn -> {:ok, Enum.slice(top_addresses_result(), 2, 2)} end
        ]
        |> Sanbase.Mock.wrap_consecutives(arity: 2)

      Sanbase.Mock.prepare_mock(
        Sanbase.Balance,
        :current_balance_top_addresses,
        mock_fun
      )
      |> Sanbase.Mock.prepare_mock2(
        &Sanbase.Clickhouse.Label.get_address_labels/2,
        {:ok, labels_result()}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        result = do_execute_mutation(conn, create_watchlist_query(function: function))

        user_list = result["data"]["createWatchlist"]

        assert user_list["name"] == "My list"
        assert user_list["type"] == "BLOCKCHAIN_ADDRESS"
        assert user_list["color"] == "BLACK"
        assert user_list["isPublic"] == false
        assert user_list["user"]["id"] == user.id |> to_string()

        assert length(user_list["listItems"]) == 0
      end)
    end
  end

  describe "addresses_by_labels blockchain address selector" do
    test "dynamic watchlist for selector with labels combinator OR", context do
      %{conn: conn} = context
      # Have at least 1 project that is not included in the result
      insert(:random_erc20_project)

      function = %{
        "name" => "address_selector",
        "args" => %{
          "filters" => [
            %{
              "name" => "addresses_by_labels",
              "args" => %{
                "blockchain" => "ethereum",
                "label_fqns" => [
                  "santiment/owner->bitfinex:v1",
                  "santiment/owner->binance:v1",
                  "santiment/whale(greenmed):v1"
                ],
                "labels_combinator" => "or"
              }
            }
          ]
        }
      }

      Sanbase.Mock.prepare_mock2(
        &Sanbase.ClickhouseRepo.query/2,
        {:ok, %{rows: addresses_by_labels_result()}}
      )
      |> Sanbase.Mock.prepare_mock2(
        &Sanbase.Clickhouse.Label.get_address_labels/2,
        {:ok, labels_result()}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        result = do_execute_mutation(conn, create_watchlist_query(function: function))

        user_list = result["data"]["createWatchlist"]

        assert length(user_list["listItems"]) == 4

        assert %{
                 "blockchainAddress" => %{
                   "address" => "0x4269cba223b56458d72bdce36afbe48996d78f24",
                   "infrastructure" => "ETH",
                   "labels" => [%{"name" => "CEX Trader", "origin" => "santiment"}]
                 }
               } in user_list["listItems"]

        assert %{
                 "blockchainAddress" => %{
                   "address" => "0x7125160a07a753b988839b004673c668012dd631",
                   "infrastructure" => "ETH",
                   "labels" => [%{"name" => "CEX Trader", "origin" => "santiment"}]
                 }
               } in user_list["listItems"]

        assert %{
                 "blockchainAddress" => %{
                   "address" => "0xa5409ec958c83c3f309868babaca7c86dcb077c1",
                   "infrastructure" => "ETH",
                   "labels" => [%{"name" => "CEX Trader", "origin" => "santiment"}]
                 }
               } in user_list["listItems"]

        assert %{
                 "blockchainAddress" => %{
                   "address" => "0xeb2629a2734e272bcc07bda959863f316f4bd4cf",
                   "infrastructure" => "ETH",
                   "labels" => [%{"name" => "CEX Trader", "origin" => "santiment"}]
                 }
               } in user_list["listItems"]
      end)
    end

    test "dynamic watchlist for selector with labels combinator AND", context do
      %{conn: conn} = context
      # Have at least 1 project that is not included in the result
      insert(:random_erc20_project)

      function = %{
        "name" => "address_selector",
        "args" => %{
          "filters" => [
            %{
              "name" => "addresses_by_labels",
              "args" => %{
                "blockchain" => "ethereum",
                "label_fqns" => [
                  "santiment/owner->bitfinex:v1",
                  "santiment/owner->binance:v1"
                ],
                "labels_combinator" => "and"
              }
            }
          ]
        }
      }

      Sanbase.Mock.prepare_mock2(
        &Sanbase.ClickhouseRepo.query/2,
        {:ok, %{rows: addresses_by_labels_result()}}
      )
      |> Sanbase.Mock.prepare_mock2(
        &Sanbase.Clickhouse.Label.get_address_labels/2,
        {:ok, labels_result()}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        result = do_execute_mutation(conn, create_watchlist_query(function: function))

        user_list = result["data"]["createWatchlist"]

        assert length(user_list["listItems"]) == 2

        assert %{
                 "blockchainAddress" => %{
                   "address" => "0x4269cba223b56458d72bdce36afbe48996d78f24",
                   "infrastructure" => "ETH",
                   "labels" => [%{"name" => "CEX Trader", "origin" => "santiment"}]
                 }
               } in user_list["listItems"]

        assert %{
                 "blockchainAddress" => %{
                   "address" => "0xeb2629a2734e272bcc07bda959863f316f4bd4cf",
                   "infrastructure" => "ETH",
                   "labels" => [%{"name" => "CEX Trader", "origin" => "santiment"}]
                 }
               } in user_list["listItems"]
      end)
    end
  end

  describe "addresses_by_label_keys blockchain address selector" do
    test "dynamic watchlist for selector with label keys", context do
      %{conn: conn} = context
      # Have at least 1 project that is not included in the result
      insert(:random_erc20_project)

      function = %{
        "name" => "address_selector",
        "args" => %{
          "filters" => [
            %{
              "name" => "addresses_by_label_keys",
              "args" => %{
                "blockchain" => "ethereum",
                "label_fqns" => ["nft_influencer"]
              }
            }
          ]
        }
      }

      Sanbase.Mock.prepare_mock2(
        &Sanbase.ClickhouseRepo.query/2,
        {:ok, %{rows: addresses_by_labels_result()}}
      )
      |> Sanbase.Mock.prepare_mock2(
        &Sanbase.Clickhouse.Label.get_address_labels/2,
        {:ok, labels_result()}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        result = do_execute_mutation(conn, create_watchlist_query(function: function))

        user_list = result["data"]["createWatchlist"]

        assert length(user_list["listItems"]) == 4

        assert %{
                 "blockchainAddress" => %{
                   "address" => "0x4269cba223b56458d72bdce36afbe48996d78f24",
                   "infrastructure" => "ETH",
                   "labels" => [%{"name" => "CEX Trader", "origin" => "santiment"}]
                 }
               } in user_list["listItems"]

        assert %{
                 "blockchainAddress" => %{
                   "address" => "0x7125160a07a753b988839b004673c668012dd631",
                   "infrastructure" => "ETH",
                   "labels" => [%{"name" => "CEX Trader", "origin" => "santiment"}]
                 }
               } in user_list["listItems"]

        assert %{
                 "blockchainAddress" => %{
                   "address" => "0xa5409ec958c83c3f309868babaca7c86dcb077c1",
                   "infrastructure" => "ETH",
                   "labels" => [%{"name" => "CEX Trader", "origin" => "santiment"}]
                 }
               } in user_list["listItems"]

        assert %{
                 "blockchainAddress" => %{
                   "address" => "0xeb2629a2734e272bcc07bda959863f316f4bd4cf",
                   "infrastructure" => "ETH",
                   "labels" => [%{"name" => "CEX Trader", "origin" => "santiment"}]
                 }
               } in user_list["listItems"]
      end)
    end
  end

  defp create_watchlist_query(opts) do
    name = Keyword.get(opts, :name, "My list")
    color = Keyword.get(opts, :color, "BLACK")
    function = Keyword.get(opts, :function) |> Jason.encode!()
    is_screener = Keyword.get(opts, :is_screener, false)

    ~s|
    mutation {
      createWatchlist(
        type: BLOCKCHAIN_ADDRESS
        name: '#{name}'
        color: #{color}
        function: '#{function}'
        isScreener: #{is_screener}
        ) {
         id
         name
         type
         color
         isPublic
         isScreener
         user{ id }
         listItems{
           blockchainAddress { address infrastructure labels { name origin } }
         }
      }
    }
    |
    |> String.replace(~r|\"|, ~S|\\"|)
    |> String.replace(~r|'|, ~S|"|)
  end

  defp update_watchlist_query(opts) do
    id = Keyword.fetch!(opts, :id)
    function = Keyword.fetch!(opts, :function) |> Jason.encode!()

    ~s|
    mutation {
      updateWatchlist(
        id: #{id},
        function: '#{function}'
      ) {
         id
         name
         color
         isPublic
         user{ id }
         listItems{
           blockchainAddress { address infrastructure labels { name origin } }
        }
      }
    }
    |
    |> String.replace(~r|\"|, ~S|\\"|)
    |> String.replace(~r|'|, ~S|"|)
  end

  defp do_execute_mutation(conn, query) do
    conn
    |> post("/graphql", mutation_skeleton(query))
    |> json_response(200)
  end

  defp addresses_by_labels_result() do
    [
      ["0x4269cba223b56458d72bdce36afbe48996d78f24", "ethereum", "santiment/owner->binance:v1"],
      ["0x4269cba223b56458d72bdce36afbe48996d78f24", "ethereum", "santiment/owner->bitfinex:v1"],
      ["0xa5409ec958c83c3f309868babaca7c86dcb077c1", "ethereum", "santiment/owner->binance:v1"],
      ["0xeb2629a2734e272bcc07bda959863f316f4bd4cf", "ethereum", "santiment/owner->binance:v1"],
      ["0xeb2629a2734e272bcc07bda959863f316f4bd4cf", "ethereum", "santiment/owner->bitfinex:v1"],
      ["0x7125160a07a753b988839b004673c668012dd631", "ethereum", "santiment/owner->binance:v1"]
    ]
  end

  defp top_addresses_result() do
    [
      %{
        address: "0x4269cba223b56458d72bdce36afbe48996d78f24",
        infrastructure: "ETH",
        balance: 4.4e7
      },
      %{
        address: "0xa5409ec958c83c3f309868babaca7c86dcb077c1",
        infrastructure: "ETH",
        balance: 3.2e7
      },
      %{
        address: "0xeb2629a2734e272bcc07bda959863f316f4bd4cf",
        infrastructure: "ETH",
        balance: 2.3e7
      },
      %{
        address: "0x7125160a07a753b988839b004673c668012dd631",
        infrastructure: "ETH",
        balance: 1.83e6
      }
    ]
  end

  defp labels_result() do
    %{
      "0x4269cba223b56458d72bdce36afbe48996d78f24" => [
        %{
          metadata: "{\"owner\": \"binance\"}",
          name: "CEX Trader",
          origin: "santiment"
        }
      ],
      "0xa5409ec958c83c3f309868babaca7c86dcb077c1" => [
        %{
          metadata: "{\"owner\": \"huobi\"}",
          name: "decentralized_exchange",
          origin: "santiment"
        }
      ],
      "0xeb2629a2734e272bcc07bda959863f316f4bd4cf" => [
        %{
          metadata: "{\"owner\": \"binance\"}",
          name: "centralized_exchange",
          origin: "santiment"
        }
      ],
      "0x7125160a07a753b988839b004673c668012dd631" => [
        %{
          metadata: "{\"owner\": \"binance\"}",
          name: "CEX Trader",
          origin: "santiment"
        }
      ]
    }
  end
end
