defmodule SanbaseWeb.Graphql.LabelsDataloader do
  @moduledoc false
  alias Sanbase.Clickhouse.Label

  def data, do: Dataloader.KV.new(&query/2)

  def query(:address_labels, addresses) do
    addresses
    |> Enum.uniq()
    |> Enum.chunk_every(50)
    |> Sanbase.Parallel.map(&get_address_labels/1,
      max_concurrency: 4,
      ordered: false,
      timeout: 55_000
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
