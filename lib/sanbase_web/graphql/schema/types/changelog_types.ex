defmodule SanbaseWeb.Graphql.ChangelogTypes do
  use Absinthe.Schema.Notation

  @desc """
  A changelog entry for a specific date containing all metrics and assets events.
  """
  object :changelog_date_entry do
    field(:date, non_null(:date), description: "Date of the changelog entry")

    field(:created_metrics, list_of(:metric_changelog_event),
      description: "Metrics created on this date"
    )

    field(:deprecated_metrics, list_of(:metric_deprecation_event),
      description: "Metrics deprecated on this date"
    )

    field(:created_assets, list_of(:asset_changelog_event),
      description: "Assets created on this date"
    )

    field(:hidden_assets, list_of(:asset_hiding_event), description: "Assets hidden on this date")
  end

  @desc """
  A metrics-only changelog entry for a specific date.
  """
  object :metrics_changelog_date_entry do
    field(:date, non_null(:date), description: "Date of the changelog entry")

    field(:created_metrics, list_of(:metric_changelog_event),
      description: "Metrics created on this date"
    )

    field(:deprecated_metrics, list_of(:metric_deprecation_event),
      description: "Metrics deprecated on this date"
    )
  end

  @desc """
  An assets-only changelog entry for a specific date.
  """
  object :assets_changelog_date_entry do
    field(:date, non_null(:date), description: "Date of the changelog entry")

    field(:created_assets, list_of(:asset_changelog_event),
      description: "Assets created on this date"
    )

    field(:hidden_assets, list_of(:asset_hiding_event), description: "Assets hidden on this date")
  end

  @desc """
  A metric creation/update event with all relevant data.
  """
  object :metric_changelog_event do
    field(:metric, non_null(:metric_info), description: "The metric information")
    field(:event_timestamp, non_null(:datetime), description: "When the event occurred")
  end

  @desc """
  A metric deprecation event with deprecation note.
  """
  object :metric_deprecation_event do
    field(:metric, non_null(:metric_info), description: "The metric information")
    field(:event_timestamp, non_null(:datetime), description: "When the event occurred")
    field(:deprecation_note, :string, description: "Optional note about the deprecation")
  end

  @desc """
  Metric information including name, identifier, and documentation links.
  """
  object :metric_info do
    field(:human_readable_name, :string, description: "Human readable name of the metric")
    field(:metric, non_null(:string), description: "Technical metric identifier")
    field(:docs, list_of(:metric_doc), description: "Documentation links for the metric")
  end

  @desc """
  Documentation link for a metric.
  """
  object :metric_doc do
    field(:link, non_null(:string), description: "URL to the documentation")
  end

  @desc """
  An asset creation event with all relevant data.
  """
  object :asset_changelog_event do
    field(:asset, non_null(:asset_info), description: "The asset information")
    field(:event_timestamp, non_null(:datetime), description: "When the event occurred")
  end

  @desc """
  An asset hiding event with hiding reason.
  """
  object :asset_hiding_event do
    field(:asset, non_null(:asset_info), description: "The asset information")
    field(:event_timestamp, non_null(:datetime), description: "When the event occurred")
    field(:hiding_reason, :string, description: "Reason for hiding the asset")
  end

  @desc """
  Asset information including name, ticker, slug, and other details.
  """
  object :asset_info do
    field(:name, non_null(:string), description: "Name of the asset")
    field(:ticker, :string, description: "Trading ticker symbol")
    field(:slug, non_null(:string), description: "URL-safe identifier")
    field(:logo_url, :string, description: "URL to the asset logo")
    field(:description, :string, description: "Description of the asset")
    field(:link, :string, description: "Link to the asset page")
  end

  @desc """
  Pagination information for changelog queries.
  """
  object :changelog_pagination do
    field(:has_more, non_null(:boolean), description: "Whether there are more entries available")
    field(:total_dates, :integer, description: "Total number of dates with changes")
    field(:current_page, :integer, description: "Current page number (for paginated results)")
    field(:total_pages, :integer, description: "Total number of pages (for paginated results)")
  end

  @desc """
  Result for metrics changelog query with pagination.
  """
  object :metrics_changelog_result do
    field(:entries, list_of(:metrics_changelog_date_entry),
      description: "Changelog entries grouped by date"
    )

    field(:pagination, non_null(:changelog_pagination), description: "Pagination information")
  end

  @desc """
  Result for assets changelog query with pagination.
  """
  object :assets_changelog_result do
    field(:entries, list_of(:assets_changelog_date_entry),
      description: "Changelog entries grouped by date"
    )

    field(:pagination, non_null(:changelog_pagination), description: "Pagination information")
  end
end
