defmodule Sanbase.MetricRegistry do
  @moduledoc ~s"""
  Public façade for the metric registry domain.

  The metric registry is split across many submodules — `Sanbase.Metric.Registry`
  holds the canonical metric definitions; `Sanbase.Metric.Registry.Changelog`,
  `.MetricVersions`, `.ChangeSuggestion`, `.Sync` cover historical/diff/sync
  views; `Sanbase.Metric.Category` and `Sanbase.Metric.UIMetadata.*` provide the
  human-facing categorization and display ordering. Web/LiveView callers should
  use this module rather than reaching into the internals directly, so the
  interaction surface stays small as the schemas evolve.

  This module is a thin shim around those submodules. It does not own state of
  its own; the underlying modules remain the source of truth and are still the
  right place for behavior changes.
  """

  alias Sanbase.Metric.Registry
  alias Sanbase.Metric.Registry.{Changelog, ChangeSuggestion, MetricVersions, Sync}
  alias Sanbase.Metric.Category
  alias Sanbase.Metric.UIMetadata

  # ── Registry CRUD/lookup ──────────────────────────────────────────────
  defdelegate all(), to: Registry
  defdelegate by_id(id), to: Registry
  defdelegate by_ids(ids), to: Registry
  defdelegate aggregations(), to: Registry
  defdelegate allowed_statuses(), to: Registry
  defdelegate resolve(list), to: Registry
  defdelegate resolve_safe(list), to: Registry
  defdelegate update_is_verified(registry, is_verified), to: Registry

  # ── Changelog / versions / suggestions / sync ─────────────────────────
  defdelegate changelog_by_metric_registry_id(id), to: Changelog, as: :by_metric_registry_id

  defdelegate changelog_state_before_last_sync(metric_registry_id, last_sync_datetime),
    to: Changelog,
    as: :state_before_last_sync

  defdelegate metric_registry_ids_with_changes(), to: Changelog

  defdelegate metric_versions_changelog(limit, offset, search_term \\ nil),
    to: MetricVersions,
    as: :get_changelog_by_date

  defdelegate change_suggestion_update_status(id, new_status),
    to: ChangeSuggestion,
    as: :update_status

  defdelegate sync_apply(params), to: Sync, as: :apply_sync
  defdelegate sync_by_uuid(uuid, sync_type), to: Sync, as: :by_uuid
  defdelegate sync_cancel_run(uuid, sync_type), to: Sync, as: :cancel_run
  defdelegate sync_last_runs(limit), to: Sync, as: :last_syncs

  defdelegate sync_mark_completed(sync_uuid, actual_changes),
    to: Sync,
    as: :mark_sync_as_completed

  defdelegate sync_run(metric_registry_ids, opts \\ []), to: Sync, as: :sync

  # ── Categorization (DB-backed Metric.Category) ────────────────────────
  defdelegate category_ordered_metrics(), to: Category, as: :get_ordered_metrics

  defdelegate category_mappings_by_metric_registry_id(id),
    to: Category,
    as: :get_mappings_by_metric_registry_id

  # ── UI metadata categories and groups ─────────────────────────────────
  defdelegate ui_category_by_name(name), to: UIMetadata.Category, as: :by_name

  defdelegate ui_group_by_name_and_category(name, category_id),
    to: UIMetadata.Group,
    as: :by_name_and_category

  defdelegate ui_groups_by_category(category_id), to: UIMetadata.Group, as: :by_category
  defdelegate ui_group_delete(group), to: UIMetadata.Group, as: :delete

  defdelegate ui_display_order_ordered_metrics(),
    to: UIMetadata.DisplayOrder,
    as: :get_ordered_metrics

  # ── Helper (registered metric modules) ────────────────────────────────
  defdelegate metric_modules(), to: Sanbase.Metric.Helper
end
