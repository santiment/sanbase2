defmodule Sanbase.Notifications.Discord.ExchangeInflow do
  @behaviour Sanbase.Notifications.Behaviour

  alias Sanbase.Model.Project
  alias Sanbase.Repo
  import Ecto.Query

  def run(opts \\ []) do
    projects =
      projects()
      |> filter_projects(opts)

    projects
    |> Enum.map(fn %Project{main_contract_address: contract} -> contract end)
    |> Sanbase.Blockchain.ExchangeFundsFlow.transactions_in(
      Timex.shift(Timex.now(), days: -1),
      Timex.now()
    )
    |> case do
      {:ok, list} ->
        publish("discord", build_payload(projects, list))

      {:error, error} ->
        nil
    end
  end

  def publish("discord", payload) do
  end

  defp projects() do
    from(
      p in Project,
      where:
        not is_nil(p.coinmarketcap_id) and not is_nil(p.main_contract_address) and
          not is_nil(p.token_decimals) and not is_nil(p.total_supply)
    )
    |> Repo.all()
  end

  defp filter_projects(projects, opts) do
    volume_threshold = Keyword.get(opts, :volume_threshold, 1_000_000)

    measurements_list =
      projects
      |> Enum.map(fn %Project{} = project -> Sanbase.Influxdb.Measurement.name_from(project) end)
      |> Enum.reject(&is_nil/1)

    case measurements_list do
      [] ->
        []

      [_ | _] ->
        measurements_str = Enum.join(measurements_list, ", ")

        volume_over_threshold_projects =
          Sanbase.Prices.Store.volume_over_threshold(
            measurements_str,
            Timex.shift(Timex.now(), days: -1),
            Timex.now(),
            volume_threshold
          )

        projects
        |> Enum.filter(fn %Project{} = project ->
          Sanbase.Influxdb.Measurement.name_from(project) in volume_over_threshold_projects
        end)
    end
  end

  defp build_payload(projects, list) do
    projects
    |> Enum.map(%Project{} = project ->

    )
  end
end
