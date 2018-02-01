defmodule Sanbase.Github.EtherbiApiTest do
  use SanbaseWeb.ConnCase

  import Mockery
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Model.{Project, Ico}
  alias Sanbase.Repo

  setup do
    Application.put_env(:sanbase, Sanbase.Etherbi, use_cache: false)

    ticker = "SAN"
    datetime1 = DateTime.from_naive!(~N[2018-01-01 12:00:00], "Etc/UTC")
    datetime2 = DateTime.from_naive!(~N[2017-01-01 21:45:00], "Etc/UTC")

    p =
      %Project{}
      |> Project.changeset(%{
        name: "Santiment",
        ticker: ticker,
        token_decimals: 18,
        coinmarketcap_id: "santiment"
      })
      |> Repo.insert!()

    %Ico{}
    |> Ico.changeset(%{
      project_id: p.id,
      main_contract_address: "0x1232",
      contract_block_number: 55,
      contract_abi: "0x321",
      rank: 1
    })
    |> Repo.insert!()

    [
      ticker: ticker,
      datetime1: datetime1,
      datetime2: datetime2
    ]
  end

  test "fetch burn rate from etherbi API", context do
    burn_rate = [
      [1_514_766_000, 91_716_892_495_405_965_698_400_256],
      [1_514_770_144, 359_319_706_108_516_227_858_038_784],
      [1_514_778_068, 31_034_050_000_000_001_245_184]
    ]

    mock(
      HTTPoison,
      :get,
      {:ok,
       %HTTPoison.Response{
         status_code: 200,
         body: Poison.encode!(burn_rate)
       }}
    )

    query = """
    {
      burnRate(
        ticker: "#{context.ticker}",
        from: "#{context.datetime1}",
        to: "#{context.datetime2}")
        {
          burnRate
        }
      }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "burnRate"))

    burn_rates = json_response(result, 200)["data"]["burnRate"]

    assert %{"burnRate" => "91716892.49540597"} in burn_rates
    assert %{"burnRate" => "359319706.1085162"} in burn_rates
    assert %{"burnRate" => "31034.050000000003"} in burn_rates
  end

  test "fetch transaction volume from Etherbi api", context do
    transaction_volume =
      Stream.cycle([
        [1_514_765_863, 5_810_803_200_000_000_000],
        [1_514_766_007, 700_000_000_000_001_803_841],
        [1_514_770_144, 1_749_612_781_540_000_000_000]
      ])
      |> Enum.take(21000)

    mock(
      HTTPoison,
      :get,
      {:ok, %HTTPoison.Response{status_code: 200, body: Poison.encode!(transaction_volume)}}
    )

    query = """
    {
      transactionVolume(
        ticker: "#{context.ticker}",
        from: "#{context.datetime1}",
        to: "#{context.datetime2}")
        {
          transactionVolume
        }
      }
    """

    result =
      context.conn
      |> post("/graphql", query_skeleton(query, "transactionVolume"))

    transaction_volumes = json_response(result, 200)["data"]["transactionVolume"]

    assert length(transaction_volumes) == 500
  end
end
