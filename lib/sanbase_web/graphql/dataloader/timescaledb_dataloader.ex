defmodule SanbaseWeb.Graphql.TimescaledbDataloader do
  alias Sanbase.Blockchain.DailyActiveAddresses
  alias Sanbase.Model.Project

  def data() do
    Dataloader.KV.new(&query/2)
  end

  def query(:average_daily_active_addresses, args) do
    args = Enum.to_list(args)
    [%{from: from, to: to} | _] = args

    Enum.map(args, fn %{project: project} ->
      case project do
        %Project{coinmarketcap_id: "ethereum"} -> "ETH"
        %Project{main_contract_address: contract_address} -> contract_address
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.chunk_every(200)
    |> Enum.flat_map(fn contract_addresses ->
      {:ok, daily_active_addresses} =
        DailyActiveAddresses.average_active_addresses(contract_addresses, from, to)

      daily_active_addresses
      |> Enum.map(fn {contract_address, addresses} ->
        {contract_address, addresses}
      end)
    end)
    |> Map.new()
  end
end
