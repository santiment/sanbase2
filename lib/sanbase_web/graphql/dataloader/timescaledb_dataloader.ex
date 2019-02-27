defmodule SanbaseWeb.Graphql.TimescaledbDataloader do
  alias Sanbase.Blockchain.DailyActiveAddresses
  alias Sanbase.Model.Project

  def data() do
    Dataloader.KV.new(&query/2)
  end

  def query(:average_daily_active_addresses, args) do
    args = Enum.to_list(args)
    [%{from: from, to: to} | _] = args

    args
    |> Enum.map(fn %{project: project} -> Project.contract_address(project) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.chunk_every(200)
    |> Sanbase.Parallel.pmap(
      fn contract_addresses ->
        {:ok, daily_active_addresses} =
          DailyActiveAddresses.average_active_addresses(contract_addresses, from, to)

        daily_active_addresses
        |> Enum.map(fn {contract_address, addresses} ->
          {contract_address, addresses}
        end)
      end,
      map_type: :flat_map
    )
    |> Map.new()
  end
end
