defmodule Sanbase.Clickhouse.Fees do
  import Sanbase.Utils.Transform, only: [maybe_apply_function: 2]

  alias Sanbase.Project
  alias Sanbase.ChRepo

  def eth_fees_distribution(from, to, limit) do
    query_struct = eth_fees_distribution_query(from, to, limit)

    ChRepo.query_transform(query_struct, & &1)
    |> maybe_apply_function(&value_fees_list_to_result/1)
  end

  def value_fees_list_to_result(data) do
    data = Enum.uniq_by(data, &Enum.at(&1, 0))

    # Get the list of projects. Returns a non-empty list when at least one of the
    # first elements in the sublists is a slug and not an address
    projects =
      Enum.map(data, &Enum.at(&1, 0))
      |> Project.List.by_field(:slug, preload?: true, preload: [:contract_addresses])

    projects_map = contract_address_to_project_map(projects)

    data
    |> enrich_data_with_projects(projects_map)
    |> transform_data_group_by_same_entity()
    |> Enum.sort_by(& &1.fees, :desc)
  end

  # If an address points to a known address, the value will be added to the
  # project's slug and not to the actual address. This helps grouping fees
  # for a project with more than one address.
  defp enrich_data_with_projects(data, projects_map) do
    Enum.map(data, fn [value, fees] ->
      case Map.get(projects_map, value) do
        %Project{slug: slug, ticker: ticker} = project ->
          %{slug: slug, ticker: ticker, project: project, address: nil, fees: fees}

        _ ->
          %{slug: nil, ticker: nil, project: nil, address: value, fees: fees}
      end
    end)
  end

  # Group the data for the same slug and for the same address. If both slug and
  # address are present, the slug takes precedence. This way if a project has
  # multiple contract addresses, the data for them will be grouped together.
  defp transform_data_group_by_same_entity(data) do
    data
    |> Enum.group_by(fn %{slug: slug, address: address} -> slug || address end)
    |> Enum.map(fn {_key, list} ->
      [elem | _] = list
      fees = Enum.map(list, & &1.fees) |> Enum.sum()
      %{elem | fees: fees}
    end)
  end

  defp contract_address_to_project_map(projects) do
    projects
    |> Enum.flat_map(fn %Project{} = project ->
      [{project.slug, project}] ++
        Enum.map(project.contract_addresses, fn %{address: address} ->
          {address |> String.downcase(), project}
        end)
    end)
    |> Map.new()
  end

  defp eth_fees_distribution_query(from, to, limit) do
    sql = """
    SELECT
      multiIf(contract = '', 'ethereum',isNull(name), contract, name) AS asset,
      fees
    FROM
    (
        SELECT name, contract, fees
        FROM
        (
            SELECT assetRefId, contract, sum(value) / 1e18 AS fees
            FROM
            (
                SELECT transactionHash, any(value) AS value
                FROM eth_transfers
                PREWHERE dt >= toDateTime({{from}}) AND dt < toDateTime({{to}}) AND type = 'fee'
                GROUP BY from, type, to, dt, transactionHash, primaryKey
            )
            ANY LEFT JOIN
            (
                SELECT transactionHash, contract, assetRefId
                FROM erc20_transfers
                WHERE dt >= toDateTime({{from}}) and dt < toDateTime({{to}})
            ) USING (transactionHash)
            GROUP BY assetRefId, contract
            ORDER BY fees DESC
            LIMIT {{limit}}
        )
        ALL LEFT JOIN
        (
          SELECT name, asset_ref_id AS assetRefId
          FROM asset_metadata FINAL
        ) USING (assetRefId)
    ) ORDER BY fees DESC
    """

    params = %{
      from: DateTime.to_unix(from),
      to: DateTime.to_unix(to),
      limit: limit
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end
end
