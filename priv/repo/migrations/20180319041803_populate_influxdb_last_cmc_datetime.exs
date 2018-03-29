defmodule Sanbase.Repo.Migrations.PopulateInfluxdbLastCmcDatetime do
  @moduledoc """
    Builds the last CMC history datetime measurement(db table).
    It should be built before running the new version because otherwise the
    fetching of history price will begin from `GraphData.fetch_first_price_datetime(coinmarketcap_id)`
  """
  use Ecto.Migration

  import Ecto.Query

  alias Sanbase.Prices.Store
  alias Sanbase.Repo
  alias Sanbase.Model.Project

  def up do
    Application.ensure_all_started(:hackney)
    start_store()

    projects()
    |> Enum.map(&import_last_datetime/1)
  end

  def down, do: :ok

  # Helper functions

  defp projects() do
    projects =
      Project
      |> where([p], not is_nil(p.coinmarketcap_id) and not is_nil(p.ticker))
      |> Repo.all()
  end

  defp start_store() do
    opts = [strategy: :one_for_one, max_restarts: 5, max_seconds: 1]
    Supervisor.start_link([Store.child_spec()], opts)
  end

  defp import_last_datetime(%Project{coinmarketcap_id: coinmarketcap_id, ticker: ticker}) do
    last_datetime_unix = last_datetime_unix(ticker)

    if last_datetime_unix > 0 do
      Store.update_last_history_datetime_cmc(
        coinmarketcap_id,
        last_datetime_unix |> DateTime.from_unix!()
      )
    end
  end

  defp last_datetime_unix(ticker) do
    last_dt_usd = do_last_datetime(ticker <> "_USD")
    last_dt_btc = do_last_datetime(ticker <> "_BTC")

    if last_dt_btc > last_dt_usd, do: last_dt_btc, else: last_dt_usd
  end

  defp do_last_datetime(pair) do
    case Store.last_datetime!(pair) do
      nil -> 0
      datetime -> datetime |> DateTime.to_unix()
    end
  end
end
