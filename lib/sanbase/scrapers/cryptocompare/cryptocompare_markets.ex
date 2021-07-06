defmodule Sanbase.Cryptocompare.Markets.Scraper do
  require Sanbase.Utils.Config, as: Config

  def run() do
    get_data()
    |> store_data()
  end

  defp get_data() do
    {:ok, %{body: body}} = HTTPoison.get(url())
    data = body |> Jason.decode!() |> Map.get("Data")

    Enum.reduce(data, %{}, fn {exchange, list}, acc ->
      Enum.reduce(list, acc, fn elem, inner_acc ->
        value = %{
          base_asset: elem["fsym"],
          quote_asset: elem["tsym"],
          exchange: exchange,
          last_update:
            elem["last_update"]
            |> Kernel.trunc()
            |> DateTime.from_unix!()
            |> DateTime.truncate(:second)
        }

        Map.update(inner_acc, elem["fsym"], [], &[value | &1])
      end)
    end)
  end

  defp store_data(data) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    data =
      data
      |> Enum.reject(fn {_key, list} -> list == [] end)
      |> Enum.flat_map(fn {_key, list} ->
        Enum.map(list, fn elem ->
          Map.merge(elem, %{source: "cryptocompare", inserted_at: now, updated_at: now})
        end)
      end)

    data
    |> Enum.chunk_every(1000)
    |> Enum.each(fn chunk ->
      Sanbase.Repo.insert_all(Sanbase.Market, chunk, on_conflict: :nothing)
    end)
  end

  defp api_key(), do: Config.module_get(Sanbase.Cryptocompare, :api_key)

  defp url() do
    "https://min-api.cryptocompare.com/data/v2/pair/mapping/exchange" <>
      "\?extraParams\=Santiment\&api_key\=#{api_key()}"
  end
end
