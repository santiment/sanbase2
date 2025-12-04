defmodule Sanbase.ExternalServices.Coinmarketcap.MetadataV2Exporter do
  @moduledoc """
  Exports the CoinMarketCap metadata v2 to a JSON file.
  """

  require Logger

  alias Sanbase.ExternalServices.Coinmarketcap
  alias Sanbase.Utils.Config

  import Ecto.Query

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

  @store_file "/tmp/cmc_metadata_v2.json"

  def save_cmc_metadata() do
    with {:ok, data} <-
           Sanbase.Project.List.projects(preload: [:latest_coinmarketcap_data])
           |> Enum.filter(& &1.coinmarketcap_id)
           |> Enum.map(& &1.coinmarketcap_id)
           |> Enum.chunk_every(200)
           |> Enum.map(&get/1)
           |> Enum.reduce(%{}, &Map.merge(&1, &2)) do
      IO.puts("Storing data to " <> @store_file)
      File.write!(@store_file, Jason.encode!(data))
    end
  end

  def get_cmc_metadata() do
    File.read!(@store_file) |> Jason.decode!()
  end

  def run() do
    Sanbase.Project.List.projects(preload: [:latest_coinmarketcap_data])
    |> Enum.filter(&(&1.coinmarketcap_id && &1.latest_coinmarketcap_data))
    |> Enum.sort_by(& &1.latest_coinmarketcap_data.rank, :asc)
    |> Enum.map(& &1.coinmarketcap_id)
    |> Enum.chunk(100)
    |> Enum.take(1)
    |> Enum.each(&get/1)
  end

  @spec get(String.t() | [String.t()]) :: {:ok, map()} | {:error, String.t()}
  def get(cmc_slugs) when is_binary(cmc_slugs) or is_list(cmc_slugs) do
    slugs_param = normalize_slugs(cmc_slugs)

    case Req.get(url(), headers: headers(), params: %{slug: slugs_param}) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      # {:ok, process_result(body, cmc_slugs)}

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

  defp normalize_slugs(slugs) when is_list(slugs), do: Enum.join(slugs, ",")
  defp normalize_slugs(slugs) when is_binary(slugs), do: slugs

  @spec process_result(map(), list()) :: map()
  def process_result(%{"data" => data}, cmc_slugs) when is_map(data) do
    cmc_slug_to_project =
      Sanbase.Project.List.projects(preload: [:contract_addresses, :infrastructure])
      |> Map.new(fn p -> {p.coinmarketcap_id, p} end)

    data
    |> tap(fn data ->
      Enum.map(data, fn {_integer_id, map} ->
        process_project_data(cmc_slug_to_project[map["slug"]], map)
      end)
    end)

    # |> Enum.map(fn {_id, crypto_data} -> extract_contract_info(crypto_data) end)
    # |> Enum.filter(&(not is_nil(&1)))
  end

  def process_result(body) do
    Logger.warning("[CMC MetadataV2] Unexpected response structure: #{inspect(body)}")
    %{}
  end

  defp process_project_data(nil, _data) do
    :ok
  end

  defp process_project_data(project, map) do
    map["contract_address"]
    |> Enum.filter(&santiment_supported_platform?/1)
    |> tap(fn contract_maps -> Enum.map(contract_maps, &generate_report(project, &1)) end)
  end

  defp generate_report(project, %{
         "contract_address" => address,
         "platform" => %{"name" => platform_name}
       }) do
    report_missing_contract_on_santiment(project, address, platform_name)
    report_contract_existing_for_wrong_project_or_platform(project, address, platform_name)
  end

  defp report_missing_contract_on_santiment(project, address, platform_name) do
    if not Map.has_key?(contract_to_project_map(), String.downcase(address)) do
      IO.puts(
        "CMC has a contract for #{project.slug} on platform #{project.infrastructure.code}: #{address}, but not on santiment"
      )
    end
  end

  defp report_contract_existing_for_wrong_project_or_platform(project, address, platform_name) do
    case Map.get(contract_to_project_map(), String.downcase(address)) do
      nil ->
        :ok

      %Sanbase.Project{} = existing_project when existing_project.id != project.id ->
        if existing_project.infrastructure &&
             existing_project.infrastructure.code !=
               @cmc_platform_name_to_infrastructure[platform_name] do
          IO.puts(
            "Contract #{address} for #{existing_project.slug} and platform #{existing_project.infrastructure && existing_project.infrastructure.code} but CMC associates it with #{project.slug} on platform #{platform_name}"
          )
        else
          :ok
        end

      _ ->
        :ok
    end
  end

  defp extract_contract_info(%{"slug" => slug, "platform" => platform}) when is_map(platform) do
    contract_address = Map.get(platform, "contract_address")
    platform_name = Map.get(platform, "name")

    if contract_address && platform_name do
      {slug, %{contract_address: contract_address, platform: platform_name}}
    else
      nil
    end
  end

  defp extract_contract_info(_), do: nil

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

  defp santiment_supported_platform?(%{"platform" => %{"name" => platform_name}}) do
    not is_nil(Map.get(@cmc_platform_name_to_infrastructure, platform_name))
  end

  defp contract_to_project_map() do
    case :persistent_term.get(:contract_to_project_map, nil) do
      nil ->
        contract_to_project = compute_contract_to_project_map()
        :persistent_term.put(:contract_to_project_map, {contract_to_project, DateTime.utc_now()})

        contract_to_project

      {contract_to_project, added_at} ->
        if DateTime.diff(DateTime.utc_now(), added_at, :minute) > 10 do
          contract_to_project = compute_contract_to_project_map()

          :persistent_term.put(
            :contract_to_project_map,
            {contract_to_project, DateTime.utc_now()}
          )

          contract_to_project
        else
          contract_to_project
        end
    end
  end

  defp compute_contract_to_project_map() do
    Sanbase.Project.List.projects(preload: [:contract_addresses, :infrastructure])
    |> Enum.flat_map(fn project ->
      project.contract_addresses |> Enum.map(fn ca -> {String.downcase(ca.address), project} end)
    end)
    |> Map.new()
  end
end
