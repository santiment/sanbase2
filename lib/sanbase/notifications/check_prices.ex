defmodule Sanbase.Notifications.CheckPrices do
  alias Sanbase.Repo
  alias Sanbase.Model.Project
  alias Sanbase.Prices.Store
  alias Sanbase.Notifications.Notification
  alias Sanbase.Notifications.Type

  import Ecto.Query
  import Sanbase.DateTimeUtils, only: [seconds_ago: 1]

  require Logger

  @notification_name "price_change"
  @cooldown_period_in_sec 60 * 10 # 10 minutes
  @check_interval_in_sec 60 * 10 # 10 minutes
  @price_change_threshold 5 # percent

  def exec do
    type_id = price_notification_type_id()

    Project
    |> Repo.all()
    |> Enum.reject(&recent_notification?(&1, type_id))
    |> Enum.map(&price_difference/1)
    |> Enum.filter(fn [price_difference, _] ->
      Kernel.abs(price_difference) > @price_change_threshold / 100
    end)
    |> Enum.map(&send_notification(&1, type_id))
  end

  defp price_difference(project) do
    Store.fetch_price_points(price_ticker(project), seconds_ago(@check_interval_in_sec), DateTime.utc_now())
    |> price_difference_for_prices(project)
  end

  defp price_difference_for_prices([], project), do: [0, project]

  defp price_difference_for_prices(prices, project) do
    [_ts, last_price | _] = List.last(prices)
    [_ts, first_price | _] = List.first(prices)

    [(last_price - first_price) / first_price, project]
  end

  defp send_notification([price_difference, %Project{name: name} = project], type_id) do
    Logger.info("Big price change of #{price_difference * 100} percent for project #{ name }: #{project_cmc_url(project)}")

    Repo.insert!(%Notification{
      project_id: project.id,
      type_id: type_id
    })
  end

  defp recent_notification?(%Project{id: id}, type_id) do
    cooldown_time = notification_cooldown_time()

    Notification
    |> where([n], project_id: ^id, type_id: ^type_id)
    |> where([n], n.inserted_at > ^cooldown_time)
    |> Repo.aggregate(:count, :id)
    |> Kernel.>(0)
  end

  defp notification_cooldown_time(), do: seconds_ago(@cooldown_period_in_sec)

  defp price_notification_type_id do
    type = Repo.get_by(Type, name: @notification_name) || Repo.insert!(%Type{name: @notification_name})

    type.id
  end

  defp project_cmc_url(%Project{coinmarketcap_id: coinmarketcap_id}) do
    "https://coinmarketcap.com/currencies/#{coinmarketcap_id}"
  end

  defp price_ticker(%Project{ticker: ticker}) do
    "#{ticker}_USD"
  end
end
