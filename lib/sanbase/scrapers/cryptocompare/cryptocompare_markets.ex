defmodule Sanbase.Cryptocompare.Markets.Scraper do
  @moduledoc false
  alias Sanbase.Utils.Config

  def run do
    store_data(get_data())
  end

  defp get_data do
    headers = [{"Authorization", "Apikey #{api_key()}"}]

    {:ok, %{body: body}} = HTTPoison.get(url(), headers)
    data = body |> Jason.decode!() |> Map.get("Data")

    Enum.reduce(data, %{}, fn {exchange, list}, acc ->
      Enum.reduce(list, acc, fn elem, inner_acc ->
        value = %{
          base_asset: elem["fsym"],
          quote_asset: elem["tsym"],
          exchange: exchange
        }

        Map.update(inner_acc, elem["fsym"], [], &[value | &1])
      end)
    end)
  end

  defp store_data(data) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

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

  defp api_key, do: Config.module_get(Sanbase.Cryptocompare, :api_key)

  defp url do
    "https://min-api.cryptocompare.com/data/v2/pair/mapping/exchange\?extraParams\=Santiment"
  end
end
