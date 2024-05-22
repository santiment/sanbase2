defmodule Sanbase.Clickhouse.Label.MetricAdapter do
  @moduledoc """
  Adapter for fetching metrics from Clickhouse
  """

  def labels_for_asset(slug) do
    sql = """
    SELECT
        display_name,
        fqn,
        owner,
        version,
        group
    FROM test_anatolii_labeled_balances_filtered_2
    WHERE asset_name = {{slug}}
    """

    params = %{slug: slug}

    query = Sanbase.Clickhouse.Query.new(sql, params)

    Sanbase.ClickhouseRepo.query_transform(query, & &1)
  end

  def timeseries_data() do
  end
end
