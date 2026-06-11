defmodule Sanbase.Changelog do
  @moduledoc ~s"""
  Unified read-side façade for the metric and asset changelogs. Web/transport
  callers should ask this module for changelog pages rather than reaching into
  `Sanbase.Metric.Registry.MetricVersions` and `Sanbase.Project.ProjectVersions`
  separately.
  """

  alias Sanbase.Metric.Registry.MetricVersions
  alias Sanbase.Project.ProjectVersions

  @doc ~s"""
  Page of metric changelog entries grouped by date. Returns
  `{entries, has_more, total_dates}` exactly as
  `MetricVersions.get_changelog_by_date/3` does.
  """
  @spec metrics_changelog(non_neg_integer(), non_neg_integer(), String.t() | nil) ::
          {list(), boolean(), non_neg_integer()}
  def metrics_changelog(limit, offset, search_term \\ nil) do
    MetricVersions.get_changelog_by_date(limit, offset, search_term)
  end

  @doc ~s"""
  Page of asset changelog entries grouped by date. Returns
  `{entries, total_dates}` exactly as
  `ProjectVersions.get_changelog_by_date/3` does.
  """
  @spec assets_changelog(non_neg_integer(), non_neg_integer(), String.t() | nil) ::
          {list(), non_neg_integer()}
  def assets_changelog(page, page_size, search_term \\ nil) do
    ProjectVersions.get_changelog_by_date(page, page_size, search_term)
  end
end
