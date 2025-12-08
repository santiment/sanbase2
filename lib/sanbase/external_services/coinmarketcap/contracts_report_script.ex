defmodule Sanbase.ExternalServices.Coinmarketcap.ContractsReportScript do
  @moduledoc """
  Exports the CoinMarketCap metadata v2 to a JSON file.
  """

  require Logger

  alias Sanbase.ExternalServices.Coinmarketcap
  alias Sanbase.Utils.Config

  import Ecto.Query

  import Sanbase.ExternalServices.Coinmarketcap.Utils,
    only: [san_contract_to_project_map: 0, cmc_contract_to_cmc_id_map: 0]

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
    data =
      Sanbase.Project.List.projects(preload: [:latest_coinmarketcap_data])
      |> Enum.filter(& &1.coinmarketcap_id)
      |> Enum.map(& &1.coinmarketcap_id)
      |> Enum.chunk_every(500)
      |> Enum.map(&get/1)
      |> Enum.map(fn {:ok, body} -> body["data"] end)
      |> Enum.reduce(%{}, &Map.merge(&1, &2))

    IO.puts("Storing data to " <> @store_file)
    IO.puts("Storing map size: #{map_size(data)}")
    File.write!(@store_file, Jason.encode!(data))
  end

  def read_cmc_metadata() do
    File.read!(@store_file)
    |> Jason.decode!()
    |> Enum.map(fn {cmc_id, map} ->
      map = %{
        map
        | "contract_address" =>
            Enum.filter(map["contract_address"], fn ca_map ->
              santiment_supported_platform?(ca_map)
            end)
      }

      {cmc_id, map}
    end)
    |> Map.new()
  end

  def contracts_from_cmc(cmc_id_or_ids) do
    Sanbase.ExternalServices.Coinmarketcap.MetadataV2Exporter.read_cmc_metadata()
    |> Enum.filter(fn {_, map} -> map["slug"] in List.wrap(cmc_id_or_ids) end)
    |> Enum.map(fn {_cmc_id, map} ->
      map
      |> Map.get("contract_address")
      |> Enum.map(&{&1["contract_address"], &1["platform"]["name"]})
    end)
  end

  def run() do
    read_cmc_metadata()
    |> generate_report()
  end

  @spec get(String.t() | [String.t()]) :: {:ok, map()} | {:error, String.t()}
  def get(cmc_slugs) when is_binary(cmc_slugs) or is_list(cmc_slugs) do
    slugs_param = normalize_slugs(cmc_slugs)

    case Req.get(url(), headers: headers(), params: %{slug: slugs_param}) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

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

  defp generate_report(map_data) do
    IO.puts("Checking #{map_size(map_data)} CMC projects for contract address mismatches")

    report_missing_contract_on_santiment(map_data)

    report_contract_mismatch_by_coinmarketcap_id(map_data)

    report_contract_existing_for_wrong_project_or_platform(map_data)

    report_wrong_santiment_infrastructure()
  end

  defp report_wrong_santiment_infrastructure() do
    san_contracts = san_contract_to_project_map()

    cmc_contracts_maps = cmc_contract_to_cmc_id_map()

    Enum.each(san_contracts, fn {address, project} ->
      case Map.get(cmc_contracts_maps, address, []) do
        [] ->
          :ok

        cmc_maps when cmc_maps != [] ->
          if project.infrastructure do
            infr = project.infrastructure.code

            if list = Map.get(cmc_contracts_maps, address) do
              if not Enum.any?(list, fn m -> m["infrastructure"] == infr end) do
                IO.puts(
                  "Infrastructure mismatch for #{address} for #{project.slug}. SAN infr: #{infr}, CMC infrs: #{Enum.map(list, fn m -> m["infrastructure"] end) |> Enum.uniq() |> Enum.join(", ")}"
                )
              end
            end
          end
      end
    end)
  end

  defp report_contract_mismatch_by_coinmarketcap_id(map_data) do
    projects = Sanbase.Project.List.projects(preload: [:contract_addresses, :infrastructure])

    san_contracts_by_cmc_id =
      projects
      |> Enum.filter(& &1.coinmarketcap_id)
      |> Enum.reduce(%{}, fn project, acc ->
        Enum.reduce(project.contract_addresses, acc, fn ca, acc_inner ->
          Map.update(
            acc_inner,
            project.coinmarketcap_id,
            MapSet.new([String.downcase(ca.address)]),
            fn set -> MapSet.put(set, String.downcase(ca.address)) end
          )
        end)
      end)

    cmc_contracts_by_cmc_id =
      Enum.reduce(map_data, %{}, fn {_integer_id, data}, acc ->
        addresses =
          Enum.map(data["contract_address"], fn %{"contract_address" => addr} ->
            String.downcase(addr)
          end)
          |> MapSet.new()

        Map.put(acc, data["slug"], addresses)
      end)

    Enum.each(san_contracts_by_cmc_id, fn {cmc_id, addresses_mapset} ->
      Enum.each(addresses_mapset, fn address ->
        if Map.get(cmc_contracts_by_cmc_id, cmc_id, MapSet.new()) |> MapSet.member?(address) do
          :ok
        else
          IO.puts(
            "Address #{address} is supported on Santiment for #{cmc_id}, but is missing from CMC"
          )
        end
      end)
    end)
  end

  defp report_missing_contract_on_santiment(map_data) do
    map_data
    |> Enum.flat_map(fn {_integer_id, map} ->
      map["contract_address"] |> Enum.map(fn m -> Map.put(m, "slug", map["slug"]) end)
    end)
    |> Enum.each(fn %{
                      "slug" => slug,
                      "contract_address" => address,
                      "platform" => %{"name" => platform_name}
                    } ->
      if santiment_supported_platform?(%{"platform" => %{"name" => platform_name}}) do
        if not Map.has_key?(san_contract_to_project_map(), String.downcase(address)) do
          IO.puts(
            "CMC data: #{String.pad_trailing(platform_name, 25)} addr for #{String.pad_trailing(slug, 30)}: #{String.pad_trailing(address, 45)} but not on santiment"
          )
        end
      end
    end)
  end

  defp report_contract_existing_for_wrong_project_or_platform(map_data) do
    cmc_slug_to_project =
      Sanbase.Project.List.projects(preload: [:contract_addresses, :infrastructure])
      |> Map.new(fn p -> {p.coinmarketcap_id, p} end)

    map_data
    |> Enum.each(fn {_integer_id, map} ->
      if p = cmc_slug_to_project[map["slug"]],
        do: do_report_contract_existing_for_wrong_project_or_platform(p, map)
    end)
  end

  defp do_report_contract_existing_for_wrong_project_or_platform(project, map) do
    contract_addresses =
      map["contract_address"]
      |> Enum.filter(&santiment_supported_platform?/1)
      |> Enum.filter(fn %{"contract_address" => address} ->
        Map.has_key?(san_contract_to_project_map(), String.downcase(address))
      end)

    if contract_addresses == [] do
      :ok
    else
      Enum.map(
        contract_addresses,
        fn %{"contract_address" => address, "platform" => %{"name" => platform_name}} ->
          existing_project = Map.get(san_contract_to_project_map(), String.downcase(address))
          cmc_infr = @cmc_platform_name_to_infrastructure[platform_name]

          cond do
            is_nil(existing_project.infrastructure) ->
              # IO.puts(
              #   "Contract #{address} on platform #{cmc_infr} is associated with proejct #{existing_project.slug} but it has no infrastructure set"
              # )
              :ok

            map["slug"] != existing_project.coinmarketcap_id and
              not String.contains?(existing_project.slug, map["slug"]) and
              not String.contains?(map["slug"], existing_project.slug) and
                String.jaro_distance(project.slug, existing_project.slug) < 0.8 ->
              IO.puts(
                "Contract #{String.pad_trailing(address, 45)} for #{String.pad_trailing(map["slug"], 30)} and platform #{String.pad_trailing(cmc_infr, 12)} but on santiment it is associated with a different slug #{existing_project.slug} and infrastructure #{existing_project.infrastructure.code}"
              )

            existing_project.infrastructure.code != cmc_infr ->
              slug_infr_maps = Map.get(cmc_contract_to_cmc_id_map(), String.downcase(address), [])

              # If none of the infra
              if not Enum.any?(slug_infr_maps, fn m ->
                   m["infrastructure"] == existing_project.infrastructure.code
                 end) do
                IO.puts(
                  "Contract #{String.pad_trailing(address, 45)} for #{String.pad_trailing(map["slug"], 30)} and platform #{String.pad_trailing(cmc_infr, 12)} but on santiment it is associated with #{existing_project.slug} and infrastructure #{existing_project.infrastructure.code}"
                )
              end

            true ->
              :ok
          end
        end
      )
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
end
