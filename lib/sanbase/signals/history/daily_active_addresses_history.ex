defmodule Sanbase.Signal.History.DailyActiveAddressesHistory do
  @moduledoc """
  Implementation of historical_trigger_points for daily active addresses.
  Currently it is bucketed in `1 day` intervals and goes 90 days back.
  """

  alias __MODULE__
  alias Sanbase.Signal.Trigger.DailyActiveAddressesSettings

  @type historical_trigger_points_type :: %{
          datetime: %DateTime{},
          active_addresses: non_neg_integer(),
          price: float(),
          triggered?: boolean(),
          percent_change: float()
        }

  defimpl Sanbase.Signal.History, for: DailyActiveAddressesSettings do
    @historical_days_from 90
    @historical_days_interval "1d"

    def get_data(slug, time_window) when is_binary(slug) do
      with {:ok, contract, _} <- Sanbase.Model.Project.contract_info_by_slug(slug) do
        Sanbase.Clickhouse.DailyActiveAddresses.average_active_addresses(
          contract,
          Timex.shift(Timex.now(),
            days: -(@historical_days_from + Sanbase.DateTimeUtils.str_to_days(time_window) - 1)
          ),
          Timex.now(),
          @historical_days_interval
        )
      end
    end

    import Sanbase.DateTimeUtils, only: [str_to_days: 1]
    import Sanbase.Signal.Utils, only: [percent_change: 2]
    import Sanbase.Signal.OperationEvaluation, only: [operation_triggered?: 2]

    alias Sanbase.Signal.History.DailyActiveAddressesHistory
    alias Sanbase.Signal.Trigger.DailyActiveAddressesSettings
    alias Sanbase.Signal.Operation

    @spec historical_trigger_points(%DailyActiveAddressesSettings{}, String.t()) ::
            {:ok, list(DailyActiveAddressesHistory.historical_trigger_points_type())}
            | {:error, String.t()}
    def historical_trigger_points(
          %DailyActiveAddressesSettings{target: %{slug: slug}, time_window: time_window} =
            settings,
          cooldown
        )
        when is_binary(slug) do
      with {:ok, data} <- get_data(slug, time_window) do
        build_result(data, settings, cooldown)
      end
    end

    defp build_result(data, settings, cooldown) do
      case Operation.type(settings.operation) do
        :percent -> build_percent_result(data, settings, cooldown)
        :absolute -> build_absolute_result(data, settings, cooldown)
      end
    end

    #
    defp build_percent_result(data, %{operation: operation} = settings, cooldown) do
      cooldown = Sanbase.DateTimeUtils.str_to_days(cooldown)

      {result, _} =
        data
        |> transform(settings, :percent)
        |> Enum.reduce({[], 0}, fn
          %{percent_change: percent_change} = elem, {acc, 0} ->
            case operation_triggered?(percent_change, operation) do
              true ->
                {[Map.put(elem, :triggered?, true) | acc], cooldown}

              false ->
                {[Map.put(elem, :triggered?, false) | acc], 0}
            end

          elem, {acc, cooldown_left} ->
            {[Map.put(elem, :triggered?, false) | acc], cooldown_left - 1}
        end)

      {:ok, result |> Enum.reverse()}
    end

    defp build_absolute_result(data, %{operation: operation} = settings, cooldown) do
      cooldown = Sanbase.DateTimeUtils.str_to_days(cooldown)

      {result, _} =
        data
        |> transform(settings, :absolute)
        |> Enum.reduce({[], 0}, fn
          %{active_addresses: active_addresses} = elem, {acc, 0} ->
            case operation_triggered?(active_addresses, operation) do
              true ->
                {[Map.put(elem, :triggered?, true) | acc], cooldown}

              false ->
                {[Map.put(elem, :triggered?, false) | acc], 0}
            end

          elem, {acc, cooldown_left} ->
            {[Map.put(elem, :triggered?, false) | acc], cooldown_left - 1}
        end)

      {:ok, result |> Enum.reverse()}
    end

    defp transform(data, settings, :absolute) do
      # More data are taken so they can be used to calculate % change
      # We do not need these previous data points when working with absolute
      # values
      Enum.drop(data, (settings.time_window |> str_to_days()) - 1)
    end

    defp transform(data, settings, :percent) do
      time_window_in_days = Enum.max([str_to_days(settings.time_window), 2])

      data
      |> Enum.chunk_every(time_window_in_days, 1, :discard)
      |> Enum.map(fn chunk ->
        last_elem = List.last(chunk)
        %{active_addresses: first_active_addresses} = List.first(chunk)
        %{active_addresses: last_active_addresses} = last_elem

        Map.put(
          last_elem,
          :percent_change,
          percent_change(first_active_addresses, last_active_addresses)
        )
      end)
    end
  end
end
