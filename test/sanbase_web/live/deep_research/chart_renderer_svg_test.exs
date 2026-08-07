defmodule SanbaseWeb.DeepResearch.ChartRenderer.SvgTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias SanbaseWeb.DeepResearch.ChartRenderer
  alias SanbaseWeb.DeepResearch.ChartRenderer.Svg

  test "pie spec renders an SVG donut with a slice per category" do
    spec = %{
      type: "pie",
      title: "Messages by source",
      slices: [%{label: "telegram", value: 40}, %{label: "reddit", value: 30}]
    }

    html = render_component(&Svg.chart/1, %{spec: spec})

    assert html =~ "<svg"
    assert html =~ "stroke-dasharray"
    assert html =~ "telegram"
    assert html =~ "Messages by source"
  end

  test "line spec renders a polyline with an area fill and a shaded spike band" do
    spec = %{
      type: "line",
      title: "SOL social volume",
      series: [%{label: "vol", points: [%{t: 1, v: 10}, %{t: 2, v: 80}, %{t: 3, v: 30}]}],
      spike: %{from: 2, to: 3}
    }

    html = render_component(&Svg.chart/1, %{spec: spec})

    assert html =~ "<polyline"
    assert html =~ "fill-opacity"
    assert html =~ "SOL social volume"
    assert html =~ "shaded = spike window"
  end

  test "unknown chart type renders nothing" do
    assert "" == String.trim(render_component(&Svg.chart/1, %{spec: %{type: "bogus"}}))
  end

  test "the default renderer is the SVG one" do
    assert ChartRenderer.impl() == Svg
  end
end
