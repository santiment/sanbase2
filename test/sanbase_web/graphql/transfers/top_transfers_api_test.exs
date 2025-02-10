defmodule SanbaseWeb.Graphql.TopTransactionsApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock, only: [assert_called: 1]
  import Sanbase.Factory
  import Sanbase.TestHelpers
  import SanbaseWeb.Graphql.TestHelpers

  @datetime1 ~U[2017-05-13 15:00:00Z]
  @datetime2 ~U[2017-05-14 16:00:00Z]
  @datetime3 ~U[2017-05-15 17:00:00Z]
  @datetime4 ~U[2017-05-16 18:00:00Z]
  @datetime5 ~U[2017-05-17 19:00:00Z]
  @datetime6 ~U[2017-05-18 20:00:00Z]

  @address1 "0xffas2df5ecf00aa47c87f2a69db2b69b3af281e9"
  @address2 "0x123f8054bf571ecd56db56f8aaf7b71b97f03ac7"
  @address3 "0x5095d24e2fa078b88b49bd1180f6b29dfe145bb5"
  @address4 "0xbbb61c88bb59a1f6dfe63ed4fe036466b3a328d1"

  setup_all_with_mocks([
    {Sanbase.ClickhouseRepo, [:passthrough], [query: fn _, _ -> {:ok, %{rows: []}} end]}
  ]) do
    []
  end

  setup do
    project = insert(:random_erc20_project)

    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)

    watchlist =
      insert(:watchlist,
        type: :blockchain_address,
        is_public: true,
        name: "My Watchlist",
        user: user
      )

    watchlist2 =
      insert(:watchlist,
        type: :blockchain_address,
        is_public: true,
        name: "My Other Watchlist",
        user: user
      )

    _ =
      insert(:watchlist,
        type: :blockchain_address,
        is_public: true,
        name: "Another user watchlist, should not be shown"
      )

    Sanbase.UserList.update_user_list(user, %{
      id: watchlist.id,
      list_items: [
        %{
          blockchain_address: %{
            address: @address1,
            infrastructure: "ETH",
            notes: "note1",
            labels: ["MyLabel1"]
          }
        },
        %{blockchain_address: %{address: @address2, infrastructure: "ETH", notes: "note2"}},
        %{
          blockchain_address: %{
            address: @address3,
            infrastructure: "ETH",
            notes: "note3",
            labels: ["MyLabel3"]
          }
        },
        %{blockchain_address: %{address: @address4, infrastructure: "ETH", notes: "note4"}}
      ]
    })

    Sanbase.UserList.update_user_list(user, %{
      id: watchlist2.id,
      list_items: [
        %{blockchain_address: %{address: @address1, infrastructure: "ETH", notes: "note5"}}
      ]
    })

    [
      watchlist: watchlist,
      watchlist2: watchlist2,
      slug: project.slug,
      conn: conn,
      datetime_from: @datetime1,
      datetime_to: @datetime6
    ]
  end

  test "top transfers for a slug", context do
    (&Sanbase.Transfers.top_transfers/5)
    |> Sanbase.Mock.prepare_mock2({:ok, all_transfers()})
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = """
      {
        topTransfers(
          slug: "#{context.slug}"
          from: "#{context.datetime_from}"
          to: "#{context.datetime_to}"){
            datetime
            trxValue
            fromAddress{
              address
              labels { name metadata }
              currentUserAddressDetails {
                notes
                labels { name }
                watchlists { id name }
              }
            }
            toAddress{
              address
              labels { name metadata }
              currentUserAddressDetails {
                notes
                labels { name }
                watchlists { id name }
              }
            }
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "topTransfers"))
        |> json_response(200)

      transfers = result["data"]["topTransfers"]
      assert_called(Sanbase.Transfers.top_transfers(:_, :_, :_, :_, :_))

      assert transfers == [
               %{
                 "datetime" => "2017-05-17T19:00:00Z",
                 "fromAddress" => %{
                   "address" => @address3,
                   "currentUserAddressDetails" => %{
                     "notes" => "note3",
                     "labels" => [%{"name" => "MyLabel3"}],
                     "watchlists" => [%{"id" => context.watchlist.id, "name" => "My Watchlist"}]
                   },
                   "labels" => []
                 },
                 "toAddress" => %{
                   "address" => @address2,
                   "currentUserAddressDetails" => %{
                     "notes" => "note2",
                     "labels" => [],
                     "watchlists" => [%{"id" => context.watchlist.id, "name" => "My Watchlist"}]
                   },
                   "labels" => []
                 },
                 "trxValue" => 4.5e4
               },
               %{
                 "datetime" => "2017-05-16T18:00:00Z",
                 "fromAddress" => %{
                   "address" => @address1,
                   "currentUserAddressDetails" => %{
                     "notes" => "note5",
                     "labels" => [%{"name" => "MyLabel1"}],
                     "watchlists" => [
                       %{"id" => context.watchlist2.id, "name" => "My Other Watchlist"},
                       %{"id" => context.watchlist.id, "name" => "My Watchlist"}
                     ]
                   },
                   "labels" => []
                 },
                 "toAddress" => %{
                   "address" => @address2,
                   "currentUserAddressDetails" => %{
                     "notes" => "note2",
                     "labels" => [],
                     "watchlists" => [%{"id" => context.watchlist.id, "name" => "My Watchlist"}]
                   },
                   "labels" => []
                 },
                 "trxValue" => 2.0e4
               },
               %{
                 "datetime" => "2017-05-13T15:00:00Z",
                 "fromAddress" => %{
                   "address" => @address2,
                   "currentUserAddressDetails" => %{
                     "notes" => "note2",
                     "labels" => [],
                     "watchlists" => [%{"id" => context.watchlist.id, "name" => "My Watchlist"}]
                   },
                   "labels" => []
                 },
                 "toAddress" => %{
                   "address" => @address1,
                   "currentUserAddressDetails" => %{
                     "notes" => "note5",
                     "labels" => [%{"name" => "MyLabel1"}],
                     "watchlists" => [
                       %{"id" => context.watchlist2.id, "name" => "My Other Watchlist"},
                       %{"id" => context.watchlist.id, "name" => "My Watchlist"}
                     ]
                   },
                   "labels" => []
                 },
                 "trxValue" => 2.0e3
               },
               %{
                 "datetime" => "2017-05-14T16:00:00Z",
                 "fromAddress" => %{
                   "address" => @address4,
                   "currentUserAddressDetails" => %{
                     "notes" => "note4",
                     "labels" => [],
                     "watchlists" => [%{"id" => context.watchlist.id, "name" => "My Watchlist"}]
                   },
                   "labels" => []
                 },
                 "toAddress" => %{
                   "address" => @address1,
                   "currentUserAddressDetails" => %{
                     "notes" => "note5",
                     "labels" => [%{"name" => "MyLabel1"}],
                     "watchlists" => [
                       %{"id" => context.watchlist2.id, "name" => "My Other Watchlist"},
                       %{"id" => context.watchlist.id, "name" => "My Watchlist"}
                     ]
                   },
                   "labels" => []
                 },
                 "trxValue" => 1.5e3
               }
             ]
    end)
  end

  test "top transfers for an address and slug", context do
    (&Sanbase.Transfers.top_wallet_transfers/7)
    |> Sanbase.Mock.prepare_mock2({:ok, address_transfers()})
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = """
      {
        topTransfers(
          slug: "#{context.slug}"
          from: "#{context.datetime_from}"
          to: "#{context.datetime_to}"
          addressSelector: {address: "#{@address1}" transaction_type: ALL}){
            datetime
            trxValue
            fromAddress{
              address
              labels { name metadata }
              currentUserAddressDetails {
                notes
                labels { name }
                watchlists { id name }
              }
            }
            toAddress{
              address
              labels { name metadata }
              currentUserAddressDetails {
                notes
                labels { name }
                watchlists { id name }
              }
            }
        }
      }
      """

      result =
        context.conn
        |> post("/graphql", query_skeleton(query, "topTransfers"))
        |> json_response(200)

      assert_called(Sanbase.Transfers.top_wallet_transfers(:_, :_, :_, :_, :_, :_, :_))
      transactions = result["data"]["topTransfers"]

      assert transactions ==
               [
                 %{
                   "datetime" => "2017-05-18T20:00:00Z",
                   "fromAddress" => %{
                     "address" => @address1,
                     "currentUserAddressDetails" => %{
                       "notes" => "note5",
                       "labels" => [%{"name" => "MyLabel1"}],
                       "watchlists" => [
                         %{"id" => context.watchlist2.id, "name" => "My Other Watchlist"},
                         %{"id" => context.watchlist.id, "name" => "My Watchlist"}
                       ]
                     },
                     "labels" => []
                   },
                   "toAddress" => %{
                     "address" => @address2,
                     "currentUserAddressDetails" => %{
                       "notes" => "note2",
                       "labels" => [],
                       "watchlists" => [%{"id" => context.watchlist.id, "name" => "My Watchlist"}]
                     },
                     "labels" => []
                   },
                   "trxValue" => 2.5e3
                 },
                 %{
                   "datetime" => "2017-05-13T15:00:00Z",
                   "fromAddress" => %{
                     "address" => @address2,
                     "currentUserAddressDetails" => %{
                       "notes" => "note2",
                       "labels" => [],
                       "watchlists" => [%{"id" => context.watchlist.id, "name" => "My Watchlist"}]
                     },
                     "labels" => []
                   },
                   "toAddress" => %{
                     "address" => @address1,
                     "currentUserAddressDetails" => %{
                       "notes" => "note5",
                       "labels" => [%{"name" => "MyLabel1"}],
                       "watchlists" => [
                         %{"id" => context.watchlist2.id, "name" => "My Other Watchlist"},
                         %{"id" => context.watchlist.id, "name" => "My Watchlist"}
                       ]
                     },
                     "labels" => []
                   },
                   "trxValue" => 1700.0
                 },
                 %{
                   "datetime" => "2017-05-15T17:00:00Z",
                   "fromAddress" => %{
                     "address" => @address1,
                     "currentUserAddressDetails" => %{
                       "notes" => "note5",
                       "labels" => [%{"name" => "MyLabel1"}],
                       "watchlists" => [
                         %{"id" => context.watchlist2.id, "name" => "My Other Watchlist"},
                         %{"id" => context.watchlist.id, "name" => "My Watchlist"}
                       ]
                     },
                     "labels" => []
                   },
                   "toAddress" => %{
                     "address" => @address2,
                     "currentUserAddressDetails" => %{
                       "notes" => "note2",
                       "labels" => [],
                       "watchlists" => [%{"id" => context.watchlist.id, "name" => "My Watchlist"}]
                     },
                     "labels" => []
                   },
                   "trxValue" => 1.5e3
                 }
               ]
    end)
  end

  describe "in page order by" do
    defp get_top_transfers(conn, slug, order_by, direction) do
      query = """
      {
        topTransfers(
          slug: "#{slug}"
          from: "utc_now-10d"
          to: "utc_now"
          inPageOrderBy: #{order_by |> Atom.to_string() |> String.upcase()}
          inPageOrderByDirection: #{direction |> Atom.to_string() |> String.upcase()}){
            datetime
            trxValue
        }
      }
      """

      (&Sanbase.Transfers.top_transfers/5)
      |> Sanbase.Mock.prepare_mock2({:ok, all_transfers()})
      |> Sanbase.Mock.run_with_mocks(fn ->
        conn
        |> post("/graphql", query_skeleton(query, "topTransfers"))
        |> json_response(200)
        |> get_in(["data", "topTransfers"])
      end)
    end

    test "order by datetime desc", context do
      assert get_top_transfers(context.conn, context.slug, :datetime, :desc) == [
               %{"datetime" => "2017-05-17T19:00:00Z", "trxValue" => 4.5e4},
               %{"datetime" => "2017-05-16T18:00:00Z", "trxValue" => 2.0e4},
               %{"datetime" => "2017-05-14T16:00:00Z", "trxValue" => 1.5e3},
               %{"datetime" => "2017-05-13T15:00:00Z", "trxValue" => 2000.0}
             ]
    end

    test "order by datetime asc", context do
      assert get_top_transfers(context.conn, context.slug, :datetime, :asc) == [
               %{"datetime" => "2017-05-13T15:00:00Z", "trxValue" => 2.0e3},
               %{"datetime" => "2017-05-14T16:00:00Z", "trxValue" => 1.5e3},
               %{"datetime" => "2017-05-16T18:00:00Z", "trxValue" => 2.0e4},
               %{"datetime" => "2017-05-17T19:00:00Z", "trxValue" => 4.5e4}
             ]
    end

    test "order by trx volume desc", context do
      assert get_top_transfers(context.conn, context.slug, :trx_value, :desc) == [
               %{"datetime" => "2017-05-17T19:00:00Z", "trxValue" => 4.5e4},
               %{"datetime" => "2017-05-16T18:00:00Z", "trxValue" => 2.0e4},
               %{"datetime" => "2017-05-13T15:00:00Z", "trxValue" => 2.0e3},
               %{"datetime" => "2017-05-14T16:00:00Z", "trxValue" => 1.5e3}
             ]
    end

    test "order by trx volume asc", context do
      assert get_top_transfers(context.conn, context.slug, :trx_value, :asc) == [
               %{"datetime" => "2017-05-14T16:00:00Z", "trxValue" => 1.5e3},
               %{"datetime" => "2017-05-13T15:00:00Z", "trxValue" => 2.0e3},
               %{"datetime" => "2017-05-16T18:00:00Z", "trxValue" => 2.0e4},
               %{"datetime" => "2017-05-17T19:00:00Z", "trxValue" => 4.5e4}
             ]
    end
  end

  # Private functions

  defp all_transfers do
    [
      %{
        datetime: @datetime1,
        from_address: @address2,
        trx_position: 0,
        to_address: @address1,
        trx_hash: "0x9a561c88bb59a1f6dfe63ed4fe036466b3a328d1d86d039377481ab7c4defe4e",
        trx_value: 2000.0
      },
      %{
        datetime: @datetime2,
        from_address: @address4,
        trx_position: 2,
        to_address: @address1,
        trx_hash: "0xccbb803caabebd3665eec49673e23ef5cd08bd0be50a2b1f1506d77a523827ce",
        trx_value: 1500.0
      },
      %{
        datetime: @datetime4,
        from_address: @address1,
        trx_position: 62,
        to_address: @address2,
        trx_hash: "0x9a561c88bb59a1f6dfe63ed4fe036466b3a328d1d86d039377481ab7c4def5a2",
        trx_value: 20_000.0
      },
      %{
        datetime: @datetime5,
        from_address: @address3,
        trx_position: 7,
        to_address: @address2,
        trx_hash: "0x9a561c88bb59a1f6dfe63ed4fe036466b3a328d1d86d039377481ab7c4def5e",
        trx_value: 45_000.0
      }
    ]
  end

  defp address_transfers do
    [
      %{
        datetime: @datetime1,
        from_address: @address2,
        trx_position: 0,
        to_address: @address1,
        trx_hash: "0x9a561c88bb59a1f6dfe63ed4fe036466b3a328d1d86d039377481ab7c4defe4e",
        trx_value: 1700.0
      },
      %{
        datetime: @datetime3,
        from_address: @address1,
        trx_position: 2,
        to_address: @address2,
        trx_hash: "0xccbb803caabebd3665eec49673e23ef5cd08bd0be50a2b1f1506d77a523827ce",
        trx_value: 1500.0
      },
      %{
        datetime: @datetime6,
        from_address: @address1,
        trx_position: 7,
        to_address: @address2,
        trx_hash: "0x9a561c88bb59a1f6dfe63ed4fe036466b3a328d1d86d039377481ab7c4defffff",
        trx_value: 2500.0
      }
    ]
  end
end
