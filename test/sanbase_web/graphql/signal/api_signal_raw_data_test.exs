defmodule SanbaseWeb.Graphql.Clickhouse.ApiSignalRawDataTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    %{user: user} = insert(:subscription_pro_sanbase, user: insert(:user))
    free_user = insert(:user)

    conn = setup_jwt_auth(build_conn(), user)
    free_conn = setup_jwt_auth(build_conn(), free_user)

    [
      conn: conn,
      free_conn: free_conn,
      from: ~U[2019-01-01 00:00:00Z],
      to: ~U[2019-01-02 00:00:00Z]
    ]
  end

  test "signal without signals filtering", context do
    %{conn: conn, from: from, to: to} = context

    # TODO: Update with different signals when they are added to the JSON file
    rows = [
      [
        DateTime.to_unix(~U[2019-01-01 00:00:00Z]),
        "dai_mint",
        "multi-collateral-dai",
        21_029,
        ~s|{"txHash": "0xecdeb8435aff6e18e08177bb94d52b2da6dd15b95aee7f442021911a7c9861e6", "address": "0x183c9077fb7b74f02d3badda6c85a19c92b1f648"}|
      ],
      [
        DateTime.to_unix(~U[2019-01-02 00:00:00Z]),
        "dai_mint",
        "multi-collateral-dai",
        12_308_120,
        ~s|{"txHash": "0x0bb27622fa4fcdf39344251e9b0776467eaa5d9dbf0f025d254f55093848f2bd", "address": "0x61c808d82a3ac53231750dadc13c777b59310bd9"}|
      ]
    ]

    (&Sanbase.ClickhouseRepo.query/2)
    |> Sanbase.Mock.prepare_mock2({:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        conn
        |> get_raw_signals(:all, :all, from, to)
        |> get_in(["data", "getRawSignals"])

      assert result == [
               %{
                 "datetime" => "2019-01-01T00:00:00Z",
                 "metadata" => %{
                   "address" => "0x183c9077fb7b74f02d3badda6c85a19c92b1f648",
                   "txHash" => "0xecdeb8435aff6e18e08177bb94d52b2da6dd15b95aee7f442021911a7c9861e6"
                 },
                 "value" => 21_029.0,
                 "signal" => "dai_mint",
                 "slug" => "multi-collateral-dai",
                 "isHidden" => false
               },
               %{
                 "datetime" => "2019-01-02T00:00:00Z",
                 "metadata" => %{
                   "address" => "0x61c808d82a3ac53231750dadc13c777b59310bd9",
                   "txHash" => "0x0bb27622fa4fcdf39344251e9b0776467eaa5d9dbf0f025d254f55093848f2bd"
                 },
                 "value" => 12_308_120.0,
                 "signal" => "dai_mint",
                 "slug" => "multi-collateral-dai",
                 "isHidden" => false
               }
             ]
    end)
  end

  test "signal with signals filtering", context do
    %{conn: conn, from: from, to: to} = context

    rows = [
      [
        DateTime.to_unix(~U[2019-01-01 00:00:00Z]),
        "dai_mint",
        "multi-collateral-dai",
        21_029,
        ~s|{"txHash": "0xecdeb8435aff6e18e08177bb94d52b2da6dd15b95aee7f442021911a7c9861e6", "address": "0x183c9077fb7b74f02d3badda6c85a19c92b1f648"}|
      ],
      [
        DateTime.to_unix(~U[2019-01-02 00:00:00Z]),
        "dai_mint",
        "multi-collateral-dai",
        12_308_120,
        ~s|{"txHash": "0x0bb27622fa4fcdf39344251e9b0776467eaa5d9dbf0f025d254f55093848f2bd", "address": "0x61c808d82a3ac53231750dadc13c777b59310bd9"}|
      ]
    ]

    (&Sanbase.ClickhouseRepo.query/2)
    |> Sanbase.Mock.prepare_mock2({:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        conn
        |> get_raw_signals(["dai_mint", "large_transactions"], :all, from, to)
        |> get_in(["data", "getRawSignals"])

      assert result == [
               %{
                 "datetime" => "2019-01-01T00:00:00Z",
                 "metadata" => %{
                   "address" => "0x183c9077fb7b74f02d3badda6c85a19c92b1f648",
                   "txHash" => "0xecdeb8435aff6e18e08177bb94d52b2da6dd15b95aee7f442021911a7c9861e6"
                 },
                 "value" => 21_029.0,
                 "signal" => "dai_mint",
                 "slug" => "multi-collateral-dai",
                 "isHidden" => false
               },
               %{
                 "datetime" => "2019-01-02T00:00:00Z",
                 "metadata" => %{
                   "address" => "0x61c808d82a3ac53231750dadc13c777b59310bd9",
                   "txHash" => "0x0bb27622fa4fcdf39344251e9b0776467eaa5d9dbf0f025d254f55093848f2bd"
                 },
                 "value" => 12_308_120.0,
                 "signal" => "dai_mint",
                 "slug" => "multi-collateral-dai",
                 "isHidden" => false
               }
             ]
    end)
  end

  test "signal with selector filtering", context do
    %{conn: conn, from: from, to: to} = context

    # When the slugs in the selector are validated they must exist
    insert(:random_erc20_project, slug: "multi-collateral-dai")
    insert(:random_erc20_project, slug: "not-dai")

    rows = [
      [
        DateTime.to_unix(~U[2019-01-01 00:00:00Z]),
        "dai_mint",
        "multi-collateral-dai",
        21_029,
        ~s|{"txHash": "0xecdeb8435aff6e18e08177bb94d52b2da6dd15b95aee7f442021911a7c9861e6", "address": "0x183c9077fb7b74f02d3badda6c85a19c92b1f648"}|
      ],
      [
        DateTime.to_unix(~U[2019-01-02 00:00:00Z]),
        "dai_mint",
        "not-dai",
        12_308_120,
        ~s|{"txHash": "0x0bb27622fa4fcdf39344251e9b0776467eaa5d9dbf0f025d254f55093848f2bd", "address": "0x61c808d82a3ac53231750dadc13c777b59310bd9"}|
      ]
    ]

    (&Sanbase.ClickhouseRepo.query/2)
    |> Sanbase.Mock.prepare_mock2({:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        conn
        |> get_raw_signals(:all, ["multi-collateral-dai"], from, to)
        |> get_in(["data", "getRawSignals"])

      assert result == [
               %{
                 "datetime" => "2019-01-01T00:00:00Z",
                 "metadata" => %{
                   "address" => "0x183c9077fb7b74f02d3badda6c85a19c92b1f648",
                   "txHash" => "0xecdeb8435aff6e18e08177bb94d52b2da6dd15b95aee7f442021911a7c9861e6"
                 },
                 "value" => 21_029.0,
                 "signal" => "dai_mint",
                 "slug" => "multi-collateral-dai",
                 "isHidden" => false
               }
             ]
    end)
  end

  test "restricted signal shown for fro user", context do
    %{free_conn: free_conn, from: from, to: to} = context
    insert(:random_erc20_project, slug: "multi-collateral-dai")

    rows = [
      [
        DateTime.to_unix(~U[2019-01-01 00:00:00Z]),
        "mcd_art_liquidations",
        "multi-collateral-dai",
        21_029,
        ~s|{"txHash": "0xecdeb8435aff6e18e08177bb94d52b2da6dd15b95aee7f442021911a7c9861e6", "address": "0x183c9077fb7b74f02d3badda6c85a19c92b1f648"}|
      ],
      [
        DateTime.to_unix(~U[2019-01-02 00:00:00Z]),
        "dai_mint",
        "multi-collateral-dai",
        12_308_120,
        ~s|{"txHash": "0x0bb27622fa4fcdf39344251e9b0776467eaa5d9dbf0f025d254f55093848f2bd", "address": "0x61c808d82a3ac53231750dadc13c777b59310bd9"}|
      ]
    ]

    (&Sanbase.ClickhouseRepo.query/2)
    |> Sanbase.Mock.prepare_mock2({:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        free_conn
        |> get_raw_signals(:all, :all, from, to)
        |> get_in(["data", "getRawSignals"])

      assert result == [
               %{
                 "datetime" => "2019-01-01T00:00:00Z",
                 "isHidden" => false,
                 "metadata" => %{
                   "address" => "0x183c9077fb7b74f02d3badda6c85a19c92b1f648",
                   "txHash" => "0xecdeb8435aff6e18e08177bb94d52b2da6dd15b95aee7f442021911a7c9861e6"
                 },
                 "signal" => "mcd_art_liquidations",
                 "slug" => "multi-collateral-dai",
                 "value" => 21_029.0
               },
               %{
                 "datetime" => "2019-01-02T00:00:00Z",
                 "metadata" => %{
                   "address" => "0x61c808d82a3ac53231750dadc13c777b59310bd9",
                   "txHash" => "0x0bb27622fa4fcdf39344251e9b0776467eaa5d9dbf0f025d254f55093848f2bd"
                 },
                 "value" => 12_308_120.0,
                 "signal" => "dai_mint",
                 "slug" => "multi-collateral-dai",
                 "isHidden" => false
               }
             ]
    end)
  end

  test "restricted signal not shown for free user", context do
    %{conn: conn, from: from, to: to} = context
    insert(:random_erc20_project, slug: "multi-collateral-dai")

    rows = [
      [
        DateTime.to_unix(~U[2019-01-01 00:00:00Z]),
        "mcd_art_liquidations",
        "multi-collateral-dai",
        21_029,
        ~s|{"txHash": "0xecdeb8435aff6e18e08177bb94d52b2da6dd15b95aee7f442021911a7c9861e6", "address": "0x183c9077fb7b74f02d3badda6c85a19c92b1f648"}|
      ],
      [
        DateTime.to_unix(~U[2019-01-02 00:00:00Z]),
        "dai_mint",
        "multi-collateral-dai",
        12_308_120,
        ~s|{"txHash": "0x0bb27622fa4fcdf39344251e9b0776467eaa5d9dbf0f025d254f55093848f2bd", "address": "0x61c808d82a3ac53231750dadc13c777b59310bd9"}|
      ]
    ]

    (&Sanbase.ClickhouseRepo.query/2)
    |> Sanbase.Mock.prepare_mock2({:ok, %{rows: rows}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        conn
        |> get_raw_signals(:all, :all, from, to)
        |> get_in(["data", "getRawSignals"])

      assert result == [
               %{
                 "datetime" => "2019-01-01T00:00:00Z",
                 "isHidden" => false,
                 "metadata" => %{
                   "address" => "0x183c9077fb7b74f02d3badda6c85a19c92b1f648",
                   "txHash" => "0xecdeb8435aff6e18e08177bb94d52b2da6dd15b95aee7f442021911a7c9861e6"
                 },
                 "signal" => "mcd_art_liquidations",
                 "slug" => "multi-collateral-dai",
                 "value" => 21_029.0
               },
               %{
                 "datetime" => "2019-01-02T00:00:00Z",
                 "metadata" => %{
                   "address" => "0x61c808d82a3ac53231750dadc13c777b59310bd9",
                   "txHash" => "0x0bb27622fa4fcdf39344251e9b0776467eaa5d9dbf0f025d254f55093848f2bd"
                 },
                 "value" => 12_308_120.0,
                 "signal" => "dai_mint",
                 "slug" => "multi-collateral-dai",
                 "isHidden" => false
               }
             ]
    end)
  end

  # Private functions

  defp get_raw_signals(conn, signals, slugs, from, to) do
    query = get_raw_signals_query(signals, slugs, from, to)

    conn
    |> post("/graphql", query_skeleton(query, "getSignal"))
    |> json_response(200)
  end

  defp get_raw_signals_query(:all, :all, from, to) do
    """
      {
        getRawSignals(from: "#{from}", to: "#{to}"){
          datetime
          signal
          slug
          value
          metadata
          isHidden
        }
      }
    """
  end

  defp get_raw_signals_query([_ | _] = signals, :all, from, to) do
    """
      {
        getRawSignals(signals: #{string_list_to_string(signals)}, from: "#{from}", to: "#{to}"){
          datetime
          signal
          slug
          value
          metadata
          isHidden
        }
      }
    """
  end

  defp get_raw_signals_query(:all, slugs, from, to) do
    slugs_str = Enum.map_join(slugs, ",", &~s/"#{&1}"/)

    """
      {
        getRawSignals(from: "#{from}", to: "#{to}", selector: {slugs: [#{slugs_str}]}){
          datetime
          signal
          slug
          value
          metadata
          isHidden
        }
      }
    """
  end
end
