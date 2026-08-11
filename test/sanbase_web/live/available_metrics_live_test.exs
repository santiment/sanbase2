defmodule SanbaseWeb.AvailableMetricsLiveTest do
  @moduledoc """
  Drives the real filter form. The unit tests cover `apply_filters/2` in
  isolation; what this adds is that the form still reaches it - the checkbox and
  the selects send the names the filter expects - and that the taxonomy ordering
  survives every filter.

  Only the metrics below get available assets, and the asset checkbox is on by
  default, so the page under test holds exactly them.
  """
  use SanbaseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Sanbase.Metric.Category.MetricCategory
  alias Sanbase.Metric.Category.MetricCategoryMapping
  alias Sanbase.Metric.Category.MetricGroup

  # These are served by an adapter module rather than the registry, so the
  # mappings are module/metric rows. They exist in every environment, which keeps
  # the test independent of what the registry seed happens to hold.
  @module "Sanbase.Price.MetricAdapter"

  # Has no docs, so the docs filter has something to put on the other side.
  @undocumented "age_distribution"

  setup do
    {:ok, category} = MetricCategory.create(%{name: "LiveTest Market", display_order: 1})

    {:ok, pricing} =
      MetricGroup.create(%{name: "Pricing", category_id: category.id, display_order: 1})

    {:ok, volume} =
      MetricGroup.create(%{name: "Volume", category_id: category.id, display_order: 2})

    # price_usd is second inside Pricing, so the taxonomy order and the
    # alphabetical order disagree on purpose.
    map_metric("price_btc", category, pricing, 1)
    map_metric("price_usd", category, pricing, 2)
    map_metric("volume_usd", category, volume, 1)

    for metric <- ["price_btc", "price_usd", "volume_usd", "marketcap_usd", @undocumented] do
      {:ok, _} =
        Sanbase.AvailableMetrics.create_or_update(%{
          metric: metric,
          available_slugs: ["bitcoin"]
        })
    end

    %{category: category, pricing: pricing, volume: volume}
  end

  defp map_metric(metric, category, group, display_order) do
    {:ok, _} =
      MetricCategoryMapping.create(%{
        module: @module,
        metric: metric,
        category_id: category.id,
        group_id: group.id,
        display_order: display_order
      })
  end

  # The metric column, in the order the page renders it.
  defp metric_rows(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find("tbody tr")
    |> Enum.reject(&(Floki.find(&1, "td[colspan]") != []))
    |> Enum.map(fn row ->
      row |> Floki.find("td") |> hd() |> Floki.text() |> String.trim()
    end)
  end

  defp section_rows(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find("tbody tr td[colspan]")
    |> Enum.map(&(Floki.text(&1) |> String.trim()))
  end

  defp change(view, params) do
    view |> element("#available-metrics-filters") |> render_change(params)
  end

  defp filter(view, params), do: view |> change(params) |> metric_rows()

  defp mount_page(conn) do
    {:ok, view, _html} = live(conn, ~p"/available_metrics")
    view
  end

  describe "the filter form" do
    test "opens on the documented asset metrics, in taxonomy order", %{conn: conn} do
      view = mount_page(conn)

      rows = view |> render() |> metric_rows()

      # Grouped first, in group order, then the ungrouped one. Alphabetically
      # marketcap_usd would come first and price_usd before price_btc.
      assert rows == ["price_btc", "price_usd", "volume_usd", "marketcap_usd"]
      refute @undocumented in rows
    end

    test "renders one heading per group", %{conn: conn, category: category} do
      view = mount_page(conn)

      assert section_rows(render(view)) == [
               "#{category.name} › Pricing",
               "#{category.name} › Volume",
               "Uncategorized"
             ]
    end

    test "filters by category and keeps the order", %{conn: conn, category: category} do
      view = mount_page(conn)

      assert filter(view, %{"category_id" => to_string(category.id)}) ==
               ["price_btc", "price_usd", "volume_usd"]
    end

    test "filters by group and keeps the order", %{
      conn: conn,
      category: category,
      pricing: pricing
    } do
      view = mount_page(conn)

      assert filter(view, %{
               "category_id" => to_string(category.id),
               "group_id" => to_string(pricing.id)
             }) == ["price_btc", "price_usd"]
    end

    test "filters uncategorized metrics", %{conn: conn} do
      view = mount_page(conn)

      assert filter(view, %{"category_id" => "none"}) == ["marketcap_usd"]
    end

    test "filters by metric name and keeps the order", %{conn: conn} do
      view = mount_page(conn)

      assert filter(view, %{"match_metric_name" => "price_"}) == ["price_btc", "price_usd"]
    end

    test "filters by supported asset", %{conn: conn} do
      view = mount_page(conn)

      assert filter(view, %{"metric_supports_asset" => "bitcoin"}) != []
      assert filter(view, %{"metric_supports_asset" => "no-such-asset"}) == []
    end

    test "the docs select filters both ways", %{conn: conn} do
      view = mount_page(conn)

      with_docs = filter(view, %{"docs" => "with"})
      without_docs = filter(view, %{"docs" => "without"})
      all = filter(view, %{"docs" => "all"})

      assert without_docs == [@undocumented]
      refute @undocumented in with_docs
      assert Enum.sort(all) == Enum.sort(with_docs ++ without_docs)
    end

    test "metrics without docs are ordered too", %{
      conn: conn,
      category: category,
      pricing: pricing
    } do
      map_metric(@undocumented, category, pricing, 3)

      view = mount_page(conn)

      assert filter(view, %{"docs" => "all", "category_id" => to_string(category.id)}) ==
               ["price_btc", "price_usd", @undocumented, "volume_usd"]
    end

    test "unchecking the asset filter widens the list", %{conn: conn} do
      view = mount_page(conn)

      # An unchecked checkbox sends no parameter at all.
      widened = filter(view, %{"only_asset_metrics" => nil, "docs" => "all"})
      narrowed = filter(view, %{"only_asset_metrics" => "on", "docs" => "all"})

      assert length(widened) > length(narrowed)
      assert narrowed -- widened == []
    end

    test "a hidden group is neither listed nor offered as a filter", %{
      conn: conn,
      category: category
    } do
      {:ok, deprecated} =
        MetricGroup.create(%{name: "Deprecated", category_id: category.id, display_order: 3})

      map_metric("marketcap_usd", category, deprecated, 1)

      view = mount_page(conn)
      html = change(view, %{"category_id" => to_string(category.id)})

      refute "marketcap_usd" in metric_rows(html)
      refute html |> group_filter_options() |> Enum.member?("Deprecated")
    end
  end

  describe "the query string" do
    test "a filtered page can be linked to", %{conn: conn, category: category} do
      {:ok, view, _html} =
        live(conn, ~p"/available_metrics?#{[category_id: category.id, docs: "all"]}")

      assert metric_rows(render(view)) == ["price_btc", "price_usd", "volume_usd"]
    end

    test "off is explicit, so a link cannot be read as the default", %{conn: conn} do
      {:ok, on, _html} = live(conn, ~p"/available_metrics?docs=all")
      {:ok, off, _html} = live(conn, ~p"/available_metrics?docs=all&only_asset_metrics=off")

      assert length(metric_rows(render(off))) > length(metric_rows(render(on)))
    end

    test "the old only_with_docs link still means with docs", %{conn: conn} do
      {:ok, legacy, _html} = live(conn, ~p"/available_metrics?only_with_docs=on")
      {:ok, current, _html} = live(conn, ~p"/available_metrics?docs=with")

      assert metric_rows(render(legacy)) == metric_rows(render(current))
    end

    test "filtering rewrites the URL, and the defaults stay out of it", %{
      conn: conn,
      category: category
    } do
      view = mount_page(conn)

      change(view, %{"docs" => "without", "category_id" => to_string(category.id)})

      assert_patched(view, "/available_metrics?docs=without&category_id=#{category.id}")
    end

    test "returning to the defaults empties the query string", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/available_metrics?docs=all")

      change(view, %{"docs" => "with", "only_asset_metrics" => "on"})

      assert_patched(view, "/available_metrics")
    end

    test "the URL survives a reload", %{conn: conn, category: category, pricing: pricing} do
      view = mount_page(conn)

      change(view, %{
        "category_id" => to_string(category.id),
        "group_id" => to_string(pricing.id),
        "docs" => "all"
      })

      path = assert_patch(view)

      {:ok, reloaded, _html} = live(conn, path)

      assert metric_rows(render(reloaded)) == ["price_btc", "price_usd"]
    end
  end

  defp group_filter_options(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find("#group-filter option")
    |> Enum.map(&(Floki.text(&1) |> String.trim()))
  end
end
