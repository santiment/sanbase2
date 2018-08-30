defmodule Sanbase.Repo.Migrations.RescrapePricesSinceBeginningOfAugust do
  use Ecto.Migration

  alias Sanbase.Prices.Store

  # There is wrong data for 3rd of August for all prices
  def up do
    Application.ensure_all_started(:hackney)
    start_store()

    second_august = DateTime.from_naive!(~N[2018-08-02 23:45:00], "Etc/UTC")

    all_with_data_after_2nd_august = Store.all_with_data_after_datetime(second_august)

    {:ok, ticker_cmc_ids} = all_with_data_after_2nd_august

    ticker_cmc_ids =
      ticker_cmc_ids
      |> Enum.map(&Enum.at(&1, 2))
      |> Enum.reject(&(&1 == nil))

    for ticker_cmc_id <- ticker_cmc_ids do
      %Sanbase.Influxdb.Measurement{
        timestamp: 0,
        fields: %{last_updated: second_august |> DateTime.to_unix(:nanoseconds)},
        tags: [ticker_cmc_id: ticker_cmc_id],
        name: Store.last_history_price_cmc_measurement()
      }
    end
    |> Store.import()
  end

  def down, do: :ok

  # Helper functions

  defp start_store() do
    opts = [strategy: :one_for_one, max_restarts: 5, max_seconds: 1]
    Supervisor.start_link([Store.child_spec()], opts)
  end
end
