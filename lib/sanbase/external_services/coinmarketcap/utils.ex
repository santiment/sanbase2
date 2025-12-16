defmodule Sanbase.ExternalServices.Coinmarketcap.Utils do
  @store_file "/tmp/cmc_metadata_v2.json"

  @metadata_url "/v2/cryptocurrency/info"
  alias Sanbase.Utils.Config
  alias Sanbase.ExternalServices.Coinmarketcap

  require Logger
  # After invocation of this function the process should execute `Process.exit(self(), :normal)`
  # There is no meaningful result to be returned here. If it does not exit
  # this case should return a special case and it should be handeled so the
  # `last_updated` is not updated when no points are written
  def wait_rate_limit(%Tesla.Env{status: 429, headers: headers}, rate_limiting_server) do
    wait_period =
      case Enum.find(headers, &match?({"retry-after", _}, &1)) do
        {_, wait_period} -> wait_period |> String.to_integer()
        _ -> 1
      end

    wait_until = Timex.shift(Timex.now(), seconds: wait_period)
    Sanbase.ExternalServices.RateLimiting.Server.wait_until(rate_limiting_server, wait_until)
  end

  def get_cmc_metadata(opts \\ []) do
    get_coinmarketcap_ids(opts)
    |> Enum.chunk_every(500)
    |> Enum.map(&get_cmc_metadata_for_slugs/1)
    |> Enum.map(fn
      {:ok, body} ->
        body["data"]

      {:error, error} ->
        Logger.error("[CMC MetadataV2] Failed to fetch metadata chunk: #{error}")
        %{}
    end)
    |> Enum.reduce(%{}, &Map.merge(&1, &2))
  end

  defp get_coinmarketcap_ids(opts) do
    case Keyword.get(opts, :coinmarketcap_ids, :all) do
      :all ->
        Sanbase.Project.List.projects(preload: [:source_slug_mappings])
        |> Enum.flat_map(fn
          %{source_slug_mappings: ssm} when is_list(ssm) ->
            Enum.filter(ssm, &(&1.source == "coinmarketcap")) |> Enum.map(& &1.slug)

          _ ->
            []
        end)

      cmc_ids when is_list(cmc_ids) ->
        cmc_ids

      cmc_id_function when is_function(cmc_id_function, 0) ->
        cmc_id_function.()
    end
  end

  def save_cmc_metadata() do
    data = get_cmc_metadata()

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

  def get_cmc_metadata_for_slugs(cmc_slugs) when is_binary(cmc_slugs) or is_list(cmc_slugs) do
    # TODO: Improve this sleep
    Process.sleep(1000)
    slugs_param = cmc_slugs |> List.wrap() |> Enum.join(",")

    # skip_invalid=true seems to not work
    case Req.get(url(), headers: headers(), params: %{skip_invalid: "true", slug: slugs_param}) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        error_msg = "CoinMarketCap API error: status #{status} - #{inspect(body)}"
        handle_cmc_api_error(body)
        Logger.error("[CMC MetadataV2] #{error_msg}")
        {:error, error_msg}

      {:error, reason} ->
        error_msg = "CoinMarketCap API request failed: #{inspect(reason)}"
        Logger.error("[CMC MetadataV2] #{error_msg}")
        {:error, error_msg}
    end
  end

  def cmc_contract_to_cmc_id_map() do
    get_or_compute_function(
      :cmc_contract_to_cmc_id_map,
      &compute_cmc_contract_to_cmc_id_map/0,
      600
    )
  end

  def san_contract_to_project_map() do
    get_or_compute_function(:san_contract_to_project_map, &compute_contract_to_project_map/0, 600)
  end

  def san_contract_to_inserted_at_map() do
    get_or_compute_function(
      :san_contract_to_inserted_at_map,
      &compute_contract_to_inserted_at_map/0,
      600
    )
  end

  def cmc_id_to_projects_map() do
    get_or_compute_function(:cmc_id_to_projects_map, &compute_cmc_id_to_projects_map/0, 600)
  end

  def cmc_platform_name_to_infrastructure() do
    %{
      "Avalanche C-Chain" => "Avalanche",
      "Ethereum" => "ETH",
      "Solana" => "Solana",
      "BNB Smart Chain (BEP20)" => "BEP20",
      "Polygon" => "Polygon",
      "Base" => "Base",
      "Arbitrum" => "Arbitrum",
      "Tron" => "Tron",
      "Optimism" => "Optimism"
    }
  end

  def special_contracts_lowercased() do
    ~w(
      eosio.token/eos
      eth
      xrp
      btc
      bch
      bnb
      ltc
      matic
      ada
      doge
      icp
      sol
      adex_contract
      aergo_contract
      aleph_contract
      antimatter_contract
      aragon_contract
      archer_dao_governance_contract
      reputation_contract
      axie_contract
      chromia_contract
      cover_contract
      dapptoken_contract
      digitex_contract
      easyfi_contract
      encrypgen_contract
      golem_contract
      kai_contract
      kucoin_contract
      kyber_contract
      loom_contract
      mantradao_contract
      morpheus_contract
      mysterium_contract
      noia_contract
      ocean_contract
      ohm_contract
      orn_contract
      reserve_rights_contract
      rocket_pool_contract
      seelen_contract
      shido_contract
      singularity_contract
      sonm_contract
      susd_contract
      snx_contract
      tellor_contract
      utrust_contract
      vidt_contract
      verasity_contract
    )
  end

  def santiment_supported_platform?(%{"platform" => %{"name" => platform_name}}) do
    not is_nil(Map.get(cmc_platform_name_to_infrastructure(), platform_name))
  end

  # Private functions

  defp compute_contract_to_project_map() do
    Sanbase.Project.List.projects(preload: [:contract_addresses, :infrastructure])
    |> Enum.flat_map(fn project ->
      project.contract_addresses |> Enum.map(fn ca -> {String.downcase(ca.address), project} end)
    end)
    |> Map.new()
  end

  defp compute_cmc_id_to_projects_map() do
    Sanbase.Project.List.projects(
      preload: [:latest_coinmarketcap_data, :infrastructure, :contract_addresses]
    )
    |> Enum.filter(& &1.coinmarketcap_id)
    |> Enum.map(&{&1.coinmarketcap_id, &1})
    |> Enum.reduce(%{}, fn {cmc_id, project}, acc ->
      Map.update(
        acc,
        cmc_id,
        [project],
        &[project | &1]
      )
    end)
  end

  defp compute_contract_to_inserted_at_map() do
    Sanbase.Repo.all(Sanbase.Project.ContractAddress)
    |> Enum.map(fn %Sanbase.Project.ContractAddress{address: address, inserted_at: inserted_at} ->
      {String.downcase(address), inserted_at}
    end)
    |> Map.new()
  end

  def compute_cmc_contract_to_cmc_id_map() do
    read_cmc_metadata()
    |> Enum.flat_map(fn {_integer_id, map} ->
      map["contract_address"]
      |> Enum.map(fn %{"contract_address" => address, "platform" => %{"name" => platform_name}} ->
        {String.downcase(address),
         %{
           "platform_name" => platform_name,
           "infrastructure" => cmc_platform_name_to_infrastructure()[platform_name],
           "slug" => map["slug"]
         }}
      end)
    end)
    |> Enum.reduce(%{}, fn {addr, m}, acc ->
      Map.update(
        acc,
        addr,
        [m],
        &[m | &1]
      )
    end)
  end

  defp get_or_compute_function(key, function, ttl_seconds)
       when is_function(function, 0) and is_integer(ttl_seconds) do
    case :persistent_term.get(key, nil) do
      nil ->
        data = function.()

        :persistent_term.put(key, {data, DateTime.utc_now()})

        data

      {data, added_at} ->
        if DateTime.diff(DateTime.utc_now(), added_at, :second) > ttl_seconds do
          data = function.()

          :persistent_term.put(
            key,
            {data, DateTime.utc_now()}
          )

          data
        else
          data
        end
    end
  end

  defp handle_cmc_api_error(body) do
    case body do
      %{"status" => %{"error_message" => error_message}} ->
        if error_message =~ "Invalid values for \"slug\"" or
             error_message =~ "Invalid value for \"slug\"" do
          regex = ~r/"slug":\s*"([^"]+)"/

          extracted_slugs =
            case Regex.run(regex, error_message) do
              [_, slugs] ->
                String.split(slugs, ",")

              _ ->
                []
            end

          Sanbase.Project.nullify_coinmarketcap_ids(extracted_slugs)
        end

      _ ->
        :ok
    end
  end

  defp api_key() do
    Config.module_get(Coinmarketcap, :api_key)
  end

  defp url() do
    base_url = Config.module_get(Coinmarketcap, :api_url)
    Path.join(base_url, @metadata_url)
  end

  defp headers() do
    [{"X-CMC_PRO_API_KEY", api_key()}]
  end
end
