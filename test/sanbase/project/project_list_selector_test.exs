defmodule Sanbase.ProjectListSelectorTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Project.ListSelector

  describe "validation caughts errors" do
    test "invalid filters_combinator" do
      selector = %{
        filters_combinator: "orr",
        filters: [
          %{
            metric: "nvt",
            dynamic_from: "1d",
            dynamic_to: "now",
            aggregation: :last,
            operator: :greater_than,
            threshold: 10
          },
          %{
            metric: "daily_active_addresses",
            dynamic_from: "1d",
            dynamic_to: "now",
            aggregation: :last,
            operator: :greater_than,
            threshold: 10
          }
        ]
      }

      {:error, error_msg} = ListSelector.valid_selector?(%{selector: selector})
      assert error_msg =~ "Unsupported filter_combinator"
    end

    test "filters must be a list of maps" do
      selector = %{
        filters: [
          metric: "nvt",
          dynamic_from: "1d",
          dynamic_to: "now",
          aggregation: :last,
          operator: :greater_than,
          threshold: 10
        ]
      }

      {:error, error_msg} = ListSelector.valid_selector?(%{selector: selector})
      assert error_msg =~ "must be a map"
    end

    test "invalid metric is caught" do
      selector = %{
        filters: [
          %{
            metric: "nvtt",
            dynamic_from: "1d",
            dynamic_to: "now",
            aggregation: :last,
            operator: :greater_than,
            threshold: 10
          }
        ]
      }

      {:error, error_msg} = ListSelector.valid_selector?(%{selector: selector})

      assert error_msg =~
               "The metric 'nvtt' is not supported, is deprecated or is mistyped. Did you mean the metric 'nvt'?"
    end
  end

  describe "fetching projects" do
    test "fetch by market segment" do
      insert(:random_project)
      insert(:random_project)

      defi_segment = insert(:market_segment, name: "DeFi")

      p1 = insert(:random_project, market_segments: [defi_segment])

      p2 =
        insert(:random_project,
          market_segments: [
            defi_segment,
            build(:market_segment, name: "Ethereum")
          ]
        )

      selector = %{
        filters: [
          %{
            name: "market_segments",
            args: %{market_segments: ["DeFi"]}
          }
        ]
      }

      {:ok, %{slugs: slugs, total_projects_count: total_projects_count}} =
        ListSelector.slugs(%{selector: selector})

      assert total_projects_count == 2
      assert p1.slug in slugs
      assert p2.slug in slugs
    end

    test "fetch by metric" do
      p1 = insert(:random_project)
      _p2 = insert(:random_project)
      p3 = insert(:random_project)
      p4 = insert(:random_project)

      selector = %{
        filters: [
          %{
            name: "metric",
            args: %{
              metric: "active_addresses_24h",
              dynamic_from: "1d",
              dynamic_to: "now",
              aggregation: :last,
              operator: :greater_than,
              threshold: 100
            }
          }
        ]
      }

      Sanbase.Mock.prepare_mock2(
        &Sanbase.Clickhouse.MetricAdapter.slugs_by_filter/6,
        {:ok, [p1.slug, p3.slug, p4.slug]}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        {:ok, %{slugs: slugs, total_projects_count: total_projects_count}} =
          ListSelector.slugs(%{selector: selector})

        assert total_projects_count == 3
        assert p1.slug in slugs
        assert p3.slug in slugs
        assert p4.slug in slugs
      end)
    end

    test "combine market segments with 'or'" do
      defi_segment = insert(:market_segment, name: "DeFi")
      mineable_segment = insert(:market_segment, name: "Mineable")

      p1 = insert(:random_project, market_segments: [defi_segment])
      p2 = insert(:random_project, market_segments: [mineable_segment])
      p3 = insert(:random_project, market_segments: [mineable_segment, defi_segment])

      selector = %{
        filters: [
          %{
            name: "market_segments",
            args: %{
              market_segments: [defi_segment.name, mineable_segment.name],
              market_segments_combinator: "or"
            }
          }
        ]
      }

      {:ok, %{slugs: slugs, total_projects_count: total_projects_count}} =
        ListSelector.slugs(%{selector: selector})

      assert total_projects_count == 3
      assert p1.slug in slugs
      assert p2.slug in slugs
      assert p3.slug in slugs
    end

    test "combine market segments with 'and'" do
      defi_segment = insert(:market_segment, name: "DeFi")
      mineable_segment = insert(:market_segment, name: "Mineable")

      _p1 = insert(:random_project, market_segments: [defi_segment])
      _p2 = insert(:random_project, market_segments: [mineable_segment])
      p3 = insert(:random_project, market_segments: [mineable_segment, defi_segment])

      selector = %{
        filters: [
          %{
            name: "market_segments",
            args: %{
              market_segments: [defi_segment.name, mineable_segment.name],
              market_segments_combinator: "and"
            }
          }
        ]
      }

      {:ok, %{slugs: slugs, total_projects_count: total_projects_count}} =
        ListSelector.slugs(%{selector: selector})

      assert total_projects_count == 1
      assert p3.slug in slugs
    end

    test "fetch by metric and market segments" do
      defi_segment = insert(:market_segment, name: "DeFi")

      p1 = insert(:random_project)
      p2 = insert(:random_project, market_segments: [defi_segment])
      p3 = insert(:random_project, market_segments: [defi_segment])
      _p4 = insert(:random_project, market_segments: [defi_segment])

      selector = %{
        filters: [
          %{
            name: "market_segments",
            args: %{market_segments: ["DeFi"]}
          },
          %{
            name: "metric",
            args: %{
              metric: "daily_active_addresses",
              dynamic_from: "1d",
              dynamic_to: "now",
              aggregation: :last,
              operator: :greater_than,
              threshold: 10
            }
          }
        ]
      }

      Sanbase.Mock.prepare_mock2(
        &Sanbase.Clickhouse.MetricAdapter.slugs_by_filter/6,
        {:ok, [p1.slug, p2.slug, p3.slug]}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        {:ok, %{slugs: slugs, total_projects_count: total_projects_count}} =
          ListSelector.slugs(%{selector: selector})

        assert total_projects_count == 2
        assert p2.slug in slugs
        assert p3.slug in slugs
      end)
    end

    test "complex operator-threshold pair" do
      p1 = insert(:random_project)
      _p2 = insert(:random_project)
      p3 = insert(:random_project)
      p4 = insert(:random_project)

      selector = %{
        filters: [
          %{
            name: "metric",
            args: %{
              metric: "active_addresses_24h",
              dynamic_from: "1d",
              dynamic_to: "now",
              aggregation: :last,
              operator: :inside_channel_inclusive,
              threshold: [100, 200]
            }
          }
        ]
      }

      Sanbase.Mock.prepare_mock2(
        &Sanbase.Clickhouse.MetricAdapter.slugs_by_filter/6,
        {:ok, [p1.slug, p3.slug, p4.slug]}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        {:ok, %{slugs: slugs, total_projects_count: total_projects_count}} =
          ListSelector.slugs(%{selector: selector})

        assert total_projects_count == 3
        assert p1.slug in slugs
        assert p3.slug in slugs
        assert p4.slug in slugs
      end)
    end

    test "with base projects [{watchlsitId: id}]" do
      p1 = insert(:random_project)
      p2 = insert(:random_project)
      p3 = insert(:random_project)
      p4 = insert(:random_project)

      selector = %{
        base_projects: [%{slugs: [p1.slug, p2.slug, p4.slug]}],
        filters: [
          %{
            name: "metric",
            args: %{
              metric: "active_addresses_24h",
              dynamic_from: "1d",
              dynamic_to: "now",
              aggregation: :last,
              operator: :inside_channel_inclusive,
              threshold: [100, 200]
            }
          }
        ]
      }

      Sanbase.Mock.prepare_mock2(
        &Sanbase.Clickhouse.MetricAdapter.slugs_by_filter/6,
        {:ok, [p1.slug, p3.slug, p4.slug]}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        {:ok, %{slugs: slugs, total_projects_count: total_projects_count}} =
          ListSelector.slugs(%{selector: selector})

        assert total_projects_count == 2
        assert p1.slug in slugs
        assert p2.slug not in slugs
        assert p3.slug not in slugs
        assert p4.slug in slugs
      end)
    end

    test "with base projects [{slugs: <list>}]" do
      p1 = insert(:random_project)
      p2 = insert(:random_project)
      p3 = insert(:random_project)
      p4 = insert(:random_project)

      user = insert(:user)
      watchlist = insert(:watchlist, user: user)

      {:ok, _} =
        Sanbase.UserList.update_user_list(user, %{
          id: watchlist.id,
          list_items: [%{project_id: p1.id}, %{project_id: p2.id}, %{project_id: p3.id}]
        })

      selector = %{
        base_projects: [%{watchlistId: watchlist.id}],
        filters: [
          %{
            name: "metric",
            args: %{
              metric: "active_addresses_24h",
              dynamic_from: "1d",
              dynamic_to: "now",
              aggregation: :last,
              operator: :inside_channel_inclusive,
              threshold: [100, 200]
            }
          }
        ]
      }

      Sanbase.Mock.prepare_mock2(
        &Sanbase.Clickhouse.MetricAdapter.slugs_by_filter/6,
        {:ok, [p1.slug, p3.slug, p4.slug]}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        {:ok, %{slugs: slugs, total_projects_count: total_projects_count}} =
          ListSelector.slugs(%{selector: selector})

        assert total_projects_count == 2
        assert p1.slug in slugs
        assert p2.slug not in slugs
        assert p3.slug in slugs
        assert p4.slug not in slugs
      end)
    end

    test "with base projects [{slugs: <list>}, {watchlistId: slug}]" do
      p1 = insert(:random_project)
      p2 = insert(:random_project)
      p3 = insert(:random_project)
      p4 = insert(:random_project)

      user = insert(:user)
      watchlist = insert(:watchlist, user: user, slug: "watchlist_slug")

      {:ok, _} =
        Sanbase.UserList.update_user_list(user, %{
          id: watchlist.id,
          list_items: [%{project_id: p1.id}]
        })

      selector = %{
        base_projects: [%{watchlistId: watchlist.id}, %{slugs: [p2.slug, p3.slug]}],
        filters: [
          %{
            name: "metric",
            args: %{
              metric: "active_addresses_24h",
              dynamic_from: "1d",
              dynamic_to: "now",
              aggregation: :last,
              operator: :inside_channel_inclusive,
              threshold: [100, 200]
            }
          }
        ]
      }

      Sanbase.Mock.prepare_mock2(
        &Sanbase.Clickhouse.MetricAdapter.slugs_by_filter/6,
        {:ok, [p1.slug, p3.slug, p4.slug]}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        {:ok, %{slugs: slugs, total_projects_count: total_projects_count}} =
          ListSelector.slugs(%{selector: selector})

        assert total_projects_count == 2
        assert p1.slug in slugs
        assert p2.slug not in slugs
        assert p3.slug in slugs
        assert p4.slug not in slugs
      end)
    end

    test "traded on exchanges" do
      p1 = insert(:random_project)
      p2 = insert(:random_project)
      p3 = insert(:random_project)
      p4 = insert(:random_project)

      insert(:source_slug_mapping, source: "cryptocompare", slug: p1.ticker, project_id: p1.id)
      insert(:source_slug_mapping, source: "cryptocompare", slug: p2.ticker, project_id: p2.id)
      insert(:source_slug_mapping, source: "cryptocompare", slug: p3.ticker, project_id: p3.id)
      insert(:source_slug_mapping, source: "cryptocompare", slug: p4.ticker, project_id: p4.id)

      insert(:market, base_asset: p1.ticker, exchange: "Binance")
      insert(:market, base_asset: p2.ticker, exchange: "Binance")
      insert(:market, base_asset: p2.ticker, exchange: "Bitfinex")
      insert(:market, base_asset: p3.ticker, exchange: "Bitfinex")
      insert(:market, base_asset: p3.ticker, exchange: "LAFinance")

      # Test OR selector
      or_selector = %{
        filters: [
          %{
            name: "traded_on_exchanges",
            args: %{exchanges: ["Binance", "Bitfinex"], exchanges_combinator: "or"}
          }
        ]
      }

      {:ok, %{slugs: slugs, total_projects_count: total_projects_count}} =
        ListSelector.slugs(%{selector: or_selector})

      assert total_projects_count == 3
      assert Enum.sort(slugs) == Enum.sort([p1.slug, p2.slug, p3.slug])

      # Test AND selector
      and_selector = %{
        filters: [
          %{
            name: "traded_on_exchanges",
            args: %{exchanges: ["Binance", "Bitfinex"], exchanges_combinator: "and"}
          }
        ]
      }

      {:ok, %{slugs: slugs, total_projects_count: total_projects_count}} =
        ListSelector.slugs(%{selector: and_selector})

      assert total_projects_count == 1
      assert slugs == [p2.slug]
    end
  end
end
