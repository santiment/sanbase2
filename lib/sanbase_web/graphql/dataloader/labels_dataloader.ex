defmodule SanbaseWeb.Graphql.LabelsDataloader do
  alias Sanbase.Clickhouse.Label

  require Logger

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
      # Above the 85s ClickHouse budget and below the 105s Dataloader.KV source
      # timeout. A chunk that still times out is killed and dropped (its addresses
      # resolve to nil) instead of exiting the whole batch. See docs/timeouts.md.
      timeout: 95_000,
      on_timeout: :kill_task,
      zip_input_on_exit: true,
      request_context: ctx
    )
    |> Enum.reduce(%{}, fn
      {:exit, {addresses, reason}}, acc ->
        Logger.warning(
          "LabelsDataloader :address_labels dropped #{length(addresses)} keys. Reason: #{inspect(reason)}"
        )

        acc

      map, acc ->
        Map.merge(acc, map)
    end)
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
