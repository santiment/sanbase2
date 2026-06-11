defmodule Sanbase.MetricRegistry do
  @moduledoc ~s"""
  Public façade for the metric-registry display/categorization read paths used
  by the web layer.

  The metric registry is split across many submodules — `Sanbase.Metric.Registry`
  holds the canonical metric definitions, `Sanbase.Metric.Category` and
  `Sanbase.Metric.UIMetadata.*` provide the human-facing categorization and
  display ordering. Web/LiveView callers should reach for this module rather
  than the internals, so the interaction surface stays small as the schemas
  evolve.

  This module is a thin shim around those submodules; it owns no state of its
  own. Delegates are added here as call sites migrate onto the façade — keep it
  limited to functions that actually have a consumer.
  """

  alias Sanbase.Metric.Category
  alias Sanbase.Metric.UIMetadata

  # ── Categorization (DB-backed Metric.Category) ────────────────────────
  defdelegate category_ordered_metrics(), to: Category, as: :get_ordered_metrics

  # ── UI metadata categories and groups ─────────────────────────────────
  defdelegate ui_category_by_name(name), to: UIMetadata.Category, as: :by_name

  defdelegate ui_group_by_name_and_category(name, category_id),
    to: UIMetadata.Group,
    as: :by_name_and_category

  defdelegate ui_display_order_ordered_metrics(),
    to: UIMetadata.DisplayOrder,
    as: :get_ordered_metrics
end
