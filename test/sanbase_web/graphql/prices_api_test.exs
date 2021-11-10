defmodule SanbaseWeb.Graphql.PricesApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Plug.Conn
  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  require Sanbase.Utils.Config, as: Config

  setup do
    project1 = insert(:random_erc20_project)
    project2 = insert(:random_erc20_project)

    [
      datetime1: ~U[2017-05-13 21:45:00Z],
      datetime2: ~U[2017-05-14 21:45:00Z],
      datetime3: ~U[2017-05-15 21:45:00Z],
      years_ago: ~U[2010-01-01 21:45:00Z],
      before_existing: ~U[2007-01-01 21:45:00Z],
      slug1: project1.slug,
      slug2: project2.slug
    ]
  end

  test "data aggregation for automatically calculated intervals", context do
    %{conn: conn, slug1: slug, datetime1: from, datetime3: to} = context

    data = [
      %{datetime: from, price_usd: 22, price_btc: 0.2, marketcap_usd: 800, volume_usd: 300},
      %{datetime: to, price_usd: 25, price_btc: 0.4, marketcap_usd: 500, volume_usd: 100}
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.Price.timeseries_data/4, {:ok, data})
    |> Sanbase.Mock.prepare_mock2(&Sanbase.Price.first_datetime/1, {:ok, from})
    |> Sanbase.Mock.run_with_mocks(fn ->
      history_price =
        get_history_price(conn, slug, from, to, nil) |> get_in(["data", "historyPrice"])

      expected_history_price = [
        %{
          "datetime" => "#{from |> DateTime.to_iso8601()}",
          "priceUsd" => 22,
          "priceBtc" => 0.2,
          "marketcapUsd" => 800,
          "volumeUsd" => 300
        },
        %{
          "datetime" => "#{to |> DateTime.to_iso8601()}",
          "priceUsd" => 25,
          "priceBtc" => 0.4,
          "marketcapUsd" => 500,
          "volumeUsd" => 100
        }
      ]

      assert history_price == expected_history_price
    end)
  end

  test "data aggregation with provided interval", context do
    %{conn: conn, slug1: slug, datetime1: from, datetime3: to} = context

    data = [
      %{datetime: from, price_usd: 22, price_btc: 0.2, marketcap_usd: 800, volume_usd: 300},
      %{datetime: to, price_usd: 25, price_btc: 0.4, marketcap_usd: 500, volume_usd: 100}
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.Price.timeseries_data/4, {:ok, data})
    |> Sanbase.Mock.prepare_mock2(&Sanbase.Price.first_datetime/1, {:ok, from})
    |> Sanbase.Mock.run_with_mocks(fn ->
      history_price =
        get_history_price(conn, slug, from, to, "2d")
        |> get_in(["data", "historyPrice"])

      expected_history_price = [
        %{
          "datetime" => "#{from |> DateTime.to_iso8601()}",
          "priceUsd" => 22,
          "priceBtc" => 0.2,
          "marketcapUsd" => 800,
          "volumeUsd" => 300
        },
        %{
          "datetime" => "#{to |> DateTime.to_iso8601()}",
          "priceUsd" => 25,
          "priceBtc" => 0.4,
          "marketcapUsd" => 500,
          "volumeUsd" => 100
        }
      ]

      assert history_price == expected_history_price
    end)
  end

  test "error if from is before 2009-01-01", context do
    %{conn: conn, slug1: slug, before_existing: from, datetime3: to} = context

    result = get_history_price(conn, slug, from, to, "1000d")

    assert result["errors"] != nil
    error = result["errors"] |> List.first()
    assert error["message"] =~ "Cryptocurrencies didn't exist before 2009-01-01 00:00:00Z"
  end

  test "too complex queries are denied", context do
    %{conn: conn, slug1: slug, years_ago: from, datetime3: to} = context

    result = get_history_price(conn, slug, from, to, "5m")
    error = result["errors"] |> List.first()
    assert String.contains?(error["message"], "too complex")
  end

  test "too complex queries pass with basic authentication", context do
    %{conn: conn, slug1: slug, years_ago: from, datetime3: to} = context

    data = [
      %{datetime: from, price_usd: 22, price_btc: 0.2, marketcap_usd: 800, volume_usd: 300},
      %{datetime: to, price_usd: 25, price_btc: 0.4, marketcap_usd: 500, volume_usd: 100}
    ]

    Sanbase.Mock.prepare_mock2(&Sanbase.Price.timeseries_data/4, {:ok, data})
    |> Sanbase.Mock.prepare_mock2(&Sanbase.Price.first_datetime/1, {:ok, from})
    |> Sanbase.Mock.run_with_mocks(fn ->
      query = history_price_query(slug, from, to, "5m")

      result =
        conn
        |> put_req_header("authorization", "Basic " <> basic_auth())
        |> post("/graphql", query_skeleton(query, "historyPrice"))
        |> json_response(200)

      assert result["data"] != nil
      assert result["errors"] == nil
    end)
  end

  test "historyPrice with TOTAL_ERC20 slug", context do
    %{conn: conn, datetime1: from, datetime3: to} = context

    data = [
      %{datetime: from, marketcap_usd: 800, volume_usd: 300},
      %{datetime: to, marketcap_usd: 500, volume_usd: 100}
    ]

    Sanbase.Mock.prepare_mock2(
      &Sanbase.Price.timeseries_data/4,
      {:ok, data}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        get_history_price(conn, "TOTAL_ERC20", from, to, "1d")
        |> get_in(["data", "historyPrice"])

      expected_result = [
        %{
          "datetime" => "#{from |> DateTime.to_iso8601()}",
          "marketcapUsd" => 800,
          "priceBtc" => nil,
          "priceUsd" => nil,
          "volumeUsd" => 300
        },
        %{
          "datetime" => "#{to |> DateTime.to_iso8601()}",
          "marketcapUsd" => 500,
          "priceBtc" => nil,
          "priceUsd" => nil,
          "volumeUsd" => 100
        }
      ]

      assert result == expected_result
    end)
  end

  test "project group stats with existing slugs returns correct stats", context do
    %{conn: conn, slug1: slug1, slug2: slug2, datetime1: from, datetime3: to} = context

    data = [
      %{slug: slug1, marketcap_usd: 800, volume_usd: 300, marketcap_percent: 0.8},
      %{slug: slug2, marketcap_usd: 200, volume_usd: 700, marketcap_percent: 0.2}
    ]

    Sanbase.Mock.prepare_mock2(
      &Sanbase.Price.aggregated_marketcap_and_volume/3,
      {:ok, data}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        get_project_group_stats(conn, [slug1, slug2], from, to)
        |> get_in(["data", "projectsListStats"])

      expected_result = [
        %{
          "volumeUsd" => 300,
          "marketcapUsd" => 800,
          "marketcapPercent" => Float.round(800 / 1000, 5),
          "slug" => slug1
        },
        %{
          "volumeUsd" => 700,
          "marketcapUsd" => 200,
          "marketcapPercent" => Float.round(200 / 1000, 5),
          "slug" => slug2
        }
      ]

      assert result == expected_result
    end)
  end

  defp get_project_group_stats(conn, slugs, from, to) do
    slugs_str = slugs |> Enum.map(fn slug -> ~s|"#{slug}"| end) |> Enum.join(",")

    query = """
    {
      projectsListStats(
        slugs: [#{slugs_str}],
        from: "#{from}",
        to: "#{to}"
      ) {
        slug
        volumeUsd
        marketcapUsd
        marketcapPercent
      }
    }
    """

    conn
    |> post("/graphql", query_skeleton(query, "projectsListStats"))
    |> json_response(200)
  end

  defp history_price_query(slug, from, to, nil) do
    """
    {
      historyPrice(
        slug: "#{slug}"
        from: "#{from}"
        to: "#{to}") {
          datetime
          priceUsd
          priceBtc
          marketcapUsd
          volumeUsd
      }
    }
    """
  end

  defp history_price_query(slug, from, to, interval) do
    """
    {
      historyPrice(
        slug: "#{slug}"
        from: "#{from}"
        to: "#{to}"
        interval: "#{interval}"){
          datetime
          priceBtc
          priceUsd
          marketcapUsd
          volumeUsd
      }
    }
    """
  end

  defp get_history_price(conn, slug, from, to, interval) do
    query = history_price_query(slug, from, to, interval)

    conn
    |> post("/graphql", query_skeleton(query, "historyPrice"))
    |> json_response(200)
  end

  defp basic_auth() do
    username = Config.module_get(SanbaseWeb.Graphql.AuthPlug, :basic_auth_username)
    password = Config.module_get(SanbaseWeb.Graphql.AuthPlug, :basic_auth_password)
    Base.encode64(username <> ":" <> password)
  end
end
