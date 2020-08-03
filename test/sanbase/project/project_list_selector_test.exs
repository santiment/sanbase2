defmodule Sanbase.Model.ProjectListSelectorTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Model.Project.ListSelector

  describe "validation caughts errors" do
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
      assert error_msg =~ "The metric 'nvtt' is not supported or is mistyped. Did you mean 'nvt'?"
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
        &Sanbase.Clickhouse.Metric.slugs_by_filter/6,
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
        &Sanbase.Clickhouse.Metric.slugs_by_filter/6,
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
  end
end
