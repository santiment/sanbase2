defmodule SanbaseWeb.AvailableMetricsComponentsTest do
  @moduledoc """
  Render tests for the available metrics table. The section headings are the
  reason this exists: they are extra `<tr>`s woven between the row `<tr>`s, which
  compilation cannot check.
  """
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias SanbaseWeb.AvailableMetricsComponents

  # The group is deliberately not one of the columns, so a group name in the
  # output can only be a heading.
  def table(assigns) do
    ~H"""
    <AvailableMetricsComponents.table_with_popover_th
      id="metrics"
      rows={@rows}
      section_label={@section_label}
    >
      <:col :let={row} label="Name">{row.metric}</:col>
      <:col :let={row} label="Frequency">{row.frequency}</:col>
    </AvailableMetricsComponents.table_with_popover_th>
    """
  end

  defp rows do
    [
      %{metric: "price_usd", frequency: "5m", group: "Pricing"},
      %{metric: "volume_usd", frequency: "1d", group: "Pricing"},
      %{metric: "social_volume", frequency: "1h", group: "Social Volume"}
    ]
  end

  defp render_table(section_label) do
    render_component(&table/1, %{rows: rows(), section_label: section_label})
  end

  test "renders one heading per section, above the rows it covers" do
    html = render_table(& &1.group)

    assert count(html, "Pricing") == 1
    assert count(html, "Social Volume") == 1

    assert index(html, "Pricing") < index(html, "price_usd")
    assert index(html, "volume_usd") < index(html, "Social Volume")
  end

  test "renders every row" do
    html = render_table(& &1.group)

    for row <- rows(), do: assert(html =~ row.metric)
  end

  test "a heading spans every column" do
    assert render_table(& &1.group) =~ ~s(colspan="2")
  end

  test "renders no headings without a section_label" do
    html = render_table(nil)

    for row <- rows(), do: assert(html =~ row.metric)
    refute html =~ "colspan"
    refute html =~ "Pricing"
  end

  defp count(html, text), do: html |> String.split(text) |> length() |> Kernel.-(1)
  defp index(html, text), do: :binary.match(html, text) |> elem(0)
end
