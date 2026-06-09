defmodule SanbaseWeb.Graphql.LabelsDataloader do
  alias Sanbase.Clickhouse.Label

  def query(:address_labels, addresses, ctx) do
    addresses
    |> Enum.uniq()
    |> Enum.chunk_every(50)
    |> Sanbase.Parallel.map(&get_address_labels/1,
      max_concurrency: 4,
      ordered: false,
      timeout: 55_000,
      request_context: ctx
    )
    |> Enum.reduce(%{}, &Map.merge(&1, &2))
  end

  # Private functions

  defp get_address_labels(addresses) do
    case Label.get_address_labels(nil, addresses) do
      {:ok, map} ->
        map

      {:error, _error} ->
        %{}
    end
  end
end
