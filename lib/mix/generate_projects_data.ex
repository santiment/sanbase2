defmodule Sanbase.Mix.GenerateProjectsData do
  alias Sanbase.Project
  import Ecto.Query
  import Sanbase.BlockchainAddress, only: [ethereum_regex: 0, bitcoin_regex: 0]

  require Jason.Helpers

  @min_marketcap 100_000_000

  def run(path) do
    IO.puts("Start generating and exporting projects data in json files")

    get_projects_data()
    |> Enum.filter(&include_project?/1)
    |> tap(fn list -> IO.puts("Fetched #{length(list)} projects. Start encoding...") end)
    |> Enum.map(&encode/1)
    |> tap(fn list -> IO.puts("Encoded #{length(list)} projects. Start exporting...") end)
    |> export_json(path)
    |> tap(fn :ok -> IO.puts("Finished exporting projects to #{path}") end)
  end

  def get_projects_data() do
    from(p in Project,
      where: not is_nil(p.slug) and p.is_hidden == false,
      left_join: contract in assoc(p, :contract_addresses),
      left_join: github in assoc(p, :github_organizations),
      left_join: infrastructure in assoc(p, :infrastructure),
      left_join: latest_cmc in assoc(p, :latest_coinmarketcap_data),
      select: %{
        slug: p.slug,
        name: p.name,
        ticker: p.ticker,
        infrastructure: infrastructure.code,
        description: p.description,
        website: p.website_link,
        twitter: p.twitter_link,
        discord: p.discord_link,
        slack: p.slack_link,
        telegram: p.telegram_link,
        reddit: p.reddit_link,
        blog: p.blog_link,
        github_organizations: github,
        contract_addresses: contract,
        latest_cmc: latest_cmc,
        coinmarketcap_id: p.coinmarketcap_id
      }
    )
    |> Sanbase.Repo.all()
  end

  def export_json(list, path) do
    Enum.each(list, fn {slug, json} ->
      path = Path.join([path, slug])
      File.mkdir_p!(path)
      File.write!(Path.join([path, "data.json"]), json)
    end)
  end

  defp encode(map) do
    slug = map[:slug] || raise("Missing slug in map list #{inspect(map)}")

    general =
      Map.take(map, [:slug, :name, :ticker, :description, :website])
      |> remove_nils()
      |> Jason.OrderedObject.new()

    social =
      Map.take(map, [:twitter, :telegram, :discord, :slack, :reddit, :blog])
      |> remove_nils()
      |> remove_wrong_social_values()
      |> Jason.OrderedObject.new()

    orgs =
      (Map.get(map, :github_organizations) || [])
      |> Enum.map(& &1.organization)

    development = %{github_organizations: orgs}

    contracts =
      (Map.get(map, :contract_addresses) || [])
      |> List.wrap()
      |> Enum.reject(&is_custom_contract/1)
      |> Enum.map(fn contract ->
        blockchain =
          Project.infrastructure_to_blockchain(map[:infrastructure]) ||
            get_blockchain_from_address(contract.address)

        [
          address: contract.address,
          blockchain: blockchain,
          decimals: contract.decimals,
          label: contract.label,
          description: contract.description
        ]
        |> remove_nils()
      end)
      |> Enum.reject(&contract_missing_or_invalid_data/1)
      |> Enum.map(&Jason.OrderedObject.new/1)

    json =
      [
        general: general,
        social: social,
        development: development,
        blockchain: %{contracts: contracts}
      ]
      |> Jason.OrderedObject.new()
      |> Jason.encode!(pretty: true)

    {slug, json}
  end

  defp get_blockchain_from_address(address) do
    cond do
      is_binary(address) and Regex.match?(ethereum_regex(), address) -> "ethereum"
      is_binary(address) and Regex.match?(bitcoin_regex(), address) -> "bitcoin"
      true -> nil
    end
  end

  defp remove_nils(keyword) do
    Enum.reject(keyword, fn {_k, v} -> v == nil end)
  end

  defp contract_missing_or_invalid_data(map) do
    available_blockchains = Sanbase.BlockchainAddress.available_blockchains()

    if is_binary(map[:address]) and is_integer(map[:decimals]) and is_binary(map[:blockchain]) and
         map[:blockchain] in available_blockchains do
      false
    else
      true
    end
  end

  defp is_custom_contract(map) do
    case Map.get(map, :address) do
      nil -> true
      # Some projects have internal custom contracts like `ETH` that are not meaningful
      # to the outside world. Some contracts have invalid format generated by
      # appending some more data after it
      address -> String.length(address) <= 10 or String.length(address) > 42
    end
  end

  # In some cases the discord field holds a slack link and vice versa. Drop them
  # if this is the case
  defp remove_wrong_social_values(kv) do
    kv =
      case Keyword.get(kv, :discord) do
        nil -> kv
        discord -> if discord =~ "slack.", do: Keyword.delete(kv, :discord), else: kv
      end

    kv =
      case Keyword.get(kv, :slack) do
        nil -> kv
        slack -> if slack =~ "discord.", do: Keyword.delete(kv, :slack), else: kv
      end

    kv
  end

  # Include santiment and projects with mcap over $#{@min_marketcap}
  defp include_project?(%{slug: "santiment"}), do: true

  defp include_project?(map) do
    has_enough_marketcap? =
      case map.latest_cmc do
        %{update_time: %NaiveDateTime{} = update_time, market_cap_usd: marketcap_usd} ->
          # Do not check projects that have not been updated in long time
          dt = NaiveDateTime.utc_now() |> Timex.shift(days: -7)

          NaiveDateTime.compare(update_time, dt) == :gt and
            Decimal.to_float(marketcap_usd) >= @min_marketcap

        _ ->
          false
      end

    has_data? =
      not is_nil(map.twitter) or
        not is_nil(map.discord) or
        not is_nil(map.slack) or
        not is_nil(map.telegram) or
        not is_nil(map.reddit) or
        not is_nil(map.blog) or
        (not is_nil(map.github_organizations) and map.github_organizations != []) or
        (not is_nil(map.contract_addresses) and map.contract_addresses != [])

    has_data? and has_enough_marketcap?
  end
end
