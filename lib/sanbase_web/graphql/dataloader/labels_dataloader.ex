defmodule SanbaseWeb.Graphql.LabelsDataloader do
  alias Sanbase.Clickhouse.Label

  @doc """
  `Dataloader.KV` batch callback. Resolves address labels for the
  batched `addresses`, threading the request `ctx` into the parallel
  ClickHouse fan-out so `activity_traces_hidden` masking applies in the
  spawned workers. Returns a map of `address => labels`.
  """
  @spec query(:address_labels, [String.t()], Sanbase.RequestContext.t() | nil) :: map()
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
