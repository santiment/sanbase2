defmodule SanbaseWeb.Graphql.LabelsDataloader do
  alias Sanbase.Clickhouse.Label

  require Logger

  @doc """
  `Dataloader.KV` batch callback. Resolves address labels for the
  batched `addresses`, threading the request `ctx` into the parallel
  ClickHouse fan-out so `activity_traces_hidden` masking applies in the
  spawned workers. Returns a map of `address => labels`, or an empty map
  if any chunk fails, so the field never resolves for only some addresses.
  """
  @spec query(:address_labels, [String.t()], Sanbase.RequestContext.t() | nil) :: map()
  def query(:address_labels, addresses, ctx) do
    addresses
    |> Enum.uniq()
    |> Enum.chunk_every(50)
    |> Sanbase.Parallel.map_or_error(&Label.get_address_labels(nil, &1),
      max_concurrency: 4,
      ordered: false,
      timeout: Sanbase.Parallel.dataloader_timeout(),
      request_context: ctx
    )
    |> case do
      {:ok, maps} ->
        Enum.reduce(maps, %{}, &Map.merge(&1, &2))

      {:error, error} ->
        Logger.warning("LabelsDataloader :address_labels failed. Reason: #{inspect(error)}")
        %{}
    end
  end
end
