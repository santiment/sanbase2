defmodule Sanbase.Clickhouse.Fees do
  import Sanbase.Utils.Transform, only: [maybe_apply_function: 2]

  alias Sanbase.Model.Project
  alias Sanbase.ClickhouseRepo

  def eth_fees_distribution(from, to, limit) do
    {query, args} = eth_fees_distribution_query(from, to, limit)

    ClickhouseRepo.query_transform(query, args, & &1)
    |> maybe_apply_function(fn data ->
      data = Enum.uniq_by(data, &Enum.at(&1, 0))

      # Get the list of projects. Returns a non-empty list when at least one of the
      # first elements in the sublists is a slug and not an address
      projects =
        Enum.map(data, &Enum.at(&1, 0))
        |> Project.List.by_field(:slug, preload?: true, preload: [:contract_addresses])

      projects_map =
        projects
        |> Enum.flat_map(fn %Project{} = project ->
          [{project.slug, project}] ++
            Enum.map(project.contract_addresses, fn %{address: address} ->
              {address |> String.downcase(), project}
            end)
        end)
        |> Map.new()

      # If an address points to a known address, the value will be added to the
      # project's slug and not to the actual address. This helps grouping fees
      # for a project with more than one address.
      Enum.map(data, fn [value, fees] ->
        case Map.get(projects_map, value) do
          %Project{} = project ->
            %{slug: project.slug, ticker: project.ticker, address: nil, fees: fees}

          _ ->
            %{slug: nil, ticker: nil, address: value, fees: fees}
        end
      end)
      |> Enum.group_by(fn %{slug: slug, address: address} -> slug || address end)
      |> Enum.map(fn {_key, list} ->
        [elem | _] = list
        fees = Enum.map(list, & &1.fees) |> Enum.sum()
        %{elem | fees: fees}
      end)
    end)
  end

  defp eth_fees_distribution_query(from, to, limit) do
    from_unix = DateTime.to_unix(from)
    to_unix = DateTime.to_unix(to)

    query = """
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
                SELECT transactionHash, value
                FROM eth_transfers FINAL
                PREWHERE dt >= toDateTime(?1) AND dt < toDateTime(?2) AND type = 'fee'
            )
            ANY LEFT JOIN
            (
                SELECT transactionHash, contract, assetRefId
                FROM erc20_transfers_union
                WHERE dt >= toDateTime(?1) and dt < toDateTime(?2)
            ) USING (transactionHash)
            GROUP BY assetRefId, contract
            ORDER BY fees DESC
            LIMIT ?3
        )
        ALL LEFT JOIN
        (
          SELECT name, asset_ref_id AS assetRefId
          FROM asset_metadata FINAL
        ) USING (assetRefId)
    ) ORDER BY fees DESC
    """

    {query, [from_unix, to_unix, limit]}
  end
end
