if Code.ensure_loaded?(Neuron) do
  defmodule Sanbase.Mix.CryptocompareSlugMapping do
    # credo:disable-for-this-file
    def run() do
      map = cryptocompare_santiment_asset_mapping()

      {unknowns, knowns} = Enum.split_with(map, &(&1.cpc == :unknown))

      IO.puts("""
      #{length(unknowns)} Santiment assets with unknown cryptocompare asset:
      ---------------------------------------------------------------
      """)

      unknowns
      |> Enum.map(fn
        %{maybe: maybe, san: san} = elem ->
          dist = String.jaro_distance(maybe.coin_name, san.name) |> Float.round(2)
          {dist, elem}

        elem ->
          {-1, elem}
      end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.each(fn {dist, elem} ->
        maybe_str =
          if maybe = Map.get(elem, :maybe), do: "| MAYBE: #{maybe.symbol}, #{maybe.coin_name}"

        IO.puts(
          ~s/(#{if dist == -1, do: "---", else: dist})SAN: #{elem.san.ticker}, #{elem.san.name}, #{elem.san.slug} | CPC: unknown #{maybe_str}/
        )
      end)

      IO.puts("""
      \n\n
      #{length(knowns)} Santiment assets with known cryptocompare asset:
      ---------------------------------------------------------------
      """)

      knowns
      |> Enum.map(fn e ->
        dist = String.jaro_distance(e.cpc.coin_name, e.san.name) |> Float.round(2)
        {dist, e}
      end)
      |> Enum.sort_by(&elem(&1, 0), :asc)
      |> Enum.each(fn {dist, elem} ->
        IO.puts(
          "(#{dist}) SAN: #{elem.san.ticker}, #{elem.san.name}, #{elem.san.slug} | CPC: #{elem.cpc.symbol}, #{elem.cpc.coin_name}"
        )
      end)
    end

    def cryptocompare_santiment_asset_mapping() do
      san = get_san_assets()
      cpc = get_cryptocompare_assets()

      cpc_map = Enum.into(cpc, %{}, fn m -> {m.key, m} end)

      Enum.group_by(san, & &1.ticker)
      |> Enum.flat_map(fn {ticker, list} -> tickers_list_to_map(list, cpc_map, ticker) end)
      |> Enum.map(&replace_unknown_with_maybe(&1, cpc))
    end

    defp tickers_list_to_map(list, cpc_map, ticker) do
      case Map.get(cpc_map, ticker) do
        nil ->
          Enum.map(list, &%{san: &1, cpc: :unknown})

        cpc_asset ->
          closest = Enum.max_by(list, &String.jaro_distance(&1.name, cpc_asset.coin_name))

          [%{san: closest, cpc: cpc_asset}] ++
            Enum.map(list -- [closest], &%{san: &1, cpc: :unknown})
      end
    end

    # In case some names are too similar we can add them as :maybe and manually check
    defp replace_unknown_with_maybe(elem, cpc) do
      case elem do
        %{cpc: :unknown, san: san} = elem ->
          maybe = Enum.max_by(cpc, &String.jaro_distance(&1.coin_name, san.name))

          case String.jaro_distance(maybe.coin_name, san.name) > 0.8 do
            true -> Map.put(elem, :maybe, maybe)
            false -> elem
          end

        elem ->
          elem
      end
    end

    def get_san_assets() do
      Neuron.Config.set(url: "https://api.santiment.net/graphql")

      {:ok, %Neuron.Response{body: %{"data" => data}}} =
        Neuron.query("{ allProjects{ slug name ticker} }")

      data["allProjects"]
      |> Enum.map(fn map ->
        %{ticker: map["ticker"], slug: map["slug"], name: map["name"]}
      end)
    end

    def get_cryptocompare_assets() do
      {:ok, %HTTPoison.Response{body: body}} =
        HTTPoison.get("https://min-api.cryptocompare.com/data/all/coinlist")

      Jason.decode!(body)["Data"]
      |> Enum.map(fn {symbol, map} ->
        %{
          key: symbol,
          symbol: map["Symbol"],
          coin_name: map["CoinName"],
          name: map["Name"]
        }
      end)
    end
  end
end
