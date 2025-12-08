defmodule Sanbase.ExternalServices.Coinmarketcap.ContractsReportScript do
  @moduledoc """
  Exports the CoinMarketCap metadata v2 to a JSON file.
  """

  require Logger

  alias Sanbase.ExternalServices.Coinmarketcap
  alias Sanbase.Utils.Config

  import Ecto.Query

  import Sanbase.ExternalServices.Coinmarketcap.Utils,
    only: [
      san_contract_to_project_map: 0,
      cmc_contract_to_cmc_id_map: 0,
      cmc_id_to_project_map: 0
    ]

  @url "/v2/cryptocurrency/info"

  @cmc_platform_name_to_infrastructure %{
    "Ethereum" => "ETH",
    "Solana" => "Solana",
    "BNB Smart Chain (BEP20)" => "BEP20",
    "Polygon" => "Polygon",
    "Base" => "Base",
    "Arbitrum" => "Arbitrum",
    "Tron" => "Tron",
    "Optimism" => "Optimism"
  }

  def work() do
    get_slugs()
    |> Enum.chunk_every(100)
    |> Enum.each(fn slugs -> do_work(slugs) end)
  end

  def do_work(slugs) do
    slugs_param = Enum.join(slugs, ",")

    case Req.get(url(), headers: headers(), params: %{slug: slugs_param}) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, process_body(body)}

      {:ok, %{status: status, body: body}} ->
        error_msg = "CoinMarketCap API error: status #{status} - #{inspect(body)}"
        Logger.error("[CMC MetadataV2] #{error_msg}")
        {:error, error_msg}

      {:error, reason} ->
        error_msg = "CoinMarketCap API request failed: #{inspect(reason)}"
        Logger.error("[CMC MetadataV2] #{error_msg}")
        {:error, error_msg}
    end
  end

  def proces_body(body) do
    body["data"]
    |> Enum.map(fn {_slug, data} ->
      %{"slug" => cmc_id, "contract_address" => contracts} = data
      project = cmc_id_to_project_map()[cmc_id]
      process_project_data(project, contracts)
    end)
  end

  def process_project_data(nil, []), do: :ok
  def process_project_data(_cmc_id, []), do: :ok

  def process_project_data(project, contracts) do
    Enum.map(contracts, fn contract ->
      %{
        "contract_address" => contract_address,
        "platform" => platform_map
      } = contract

      platform_name = platform_map["name"]
      infrastructure = Map.get(@cmc_platform_name_to_infrastructure, platform_name, "Other")

      %{
        "cmc_id" => cmc_id,
        "contract_address" => String.downcase(contract_address),
        "infrastructure" => infrastructure
      }
    end)
  end

  def get_slugs() do
    data =
      Sanbase.Project.List.projects(preload: [:latest_coinmarketcap_data])
      |> Enum.filter(& &1.coinmarketcap_id)
      |> Enum.map(& &1.coinmarketcap_id)
  end

  def api_key() do
    Config.module_get(Coinmarketcap, :api_key)
  end

  def url() do
    base_url = Config.module_get(Coinmarketcap, :api_url)
    Path.join(base_url, @url)
  end

  defp headers() do
    headers = [{"X-CMC_PRO_API_KEY", api_key()}]
  end
end
