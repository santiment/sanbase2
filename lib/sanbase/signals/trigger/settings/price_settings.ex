defmodule Sanbase.Signal.Trigger.PriceSettings do
  @moduledoc ~s"""
  PriceSettings configures the settings for a signal that is fired
  when the price of `target` moves up or down by specified percent for the
  specified `time_window` time.
  """
  use Vex.Struct

  import Sanbase.{Validation, Signal.Validation}
  import Sanbase.Signal.Utils
  import Sanbase.DateTimeUtils, only: [str_to_sec: 1, interval_to_str: 1, round_datetime: 2]

  alias __MODULE__
  alias Sanbase.Signal.Type
  alias Sanbase.Model.Project
  alias Sanbase.Signal.Evaluator.Cache

  @derive {Jason.Encoder, except: [:filtered_target, :payload, :triggered?]}
  @trigger_type "price"
  @enforce_keys [:type, :target, :channel, :time_window]
  defstruct type: @trigger_type,
            target: nil,
            filtered_target: %{list: []},
            channel: nil,
            time_window: nil,
            operation: %{},
            triggered?: false,
            payload: nil

  @type t :: %__MODULE__{
          type: Type.trigger_type(),
          target: Type.complex_target(),
          filtered_target: Type.filtered_target(),
          channel: Type.channel(),
          time_window: Type.time_window(),
          operation: Type.operation(),
          triggered?: boolean(),
          payload: Type.payload()
        }

  validates(:target, &valid_target?/1)
  validates(:channel, &valid_notification_channel?/1)
  validates(:time_window, &valid_time_window?/1)
  validates(:operation, &valid_operation?/1)

  @spec type() :: Type.trigger_type()
  def type(), do: @trigger_type

  @spec get_data(__MODULE__.t()) :: list({Type.target(), any()})
  def get_data(%__MODULE__{filtered_target: %{list: target_list}} = settings)
      when is_list(target_list) do
    time_window_sec = str_to_sec(settings.time_window)
    projects = Project.by_slug(target_list)
    to = Timex.now()
    from = Timex.shift(to, seconds: -time_window_sec)

    projects
    |> Enum.map(&get_price(&1, from, to))
    |> Enum.reject(&is_nil/1)
  end

  defp get_price(project, from, to) do
    cache_key =
      {:price_signal, project.slug, round_datetime(from, 300), round_datetime(to, 300)}
      |> :erlang.phash2()

    Cache.get_or_store(
      cache_key,
      fn ->
        Sanbase.Prices.Store.first_last_price(
          Sanbase.Influxdb.Measurement.name_from(project),
          from,
          to
        )
        |> case do
          {:ok, [[_dt, first_usd_price, last_usd_price]]} ->
            data = [
              %{datetime: from, value: first_usd_price},
              %{datetime: to, value: last_usd_price}
            ]

            {project.slug, data}

          _error ->
            {project.slug, nil}
        end
      end
    )
  end

  defimpl Sanbase.Signal.Settings, for: PriceSettings do
    alias Sanbase.Signal.ResultBuilder

    def triggered?(%PriceSettings{triggered?: triggered}), do: triggered

    def evaluate(%PriceSettings{} = settings, _trigger) do
      case PriceSettings.get_data(settings) do
        data when is_list(data) and data != [] ->
          build_result(data, settings)

        _ ->
          %PriceSettings{settings | triggered?: false}
      end
    end

    defp build_result(
           data,
           %PriceSettings{} = settings
         ) do
      ResultBuilder.build(data, settings, &payload/2, value_key: :value)
    end

    @doc ~s"""
    Construct a cache key only out of the parameters that determine the outcome.
    Parameters like `channel` are discarded. The `type` is included
    so different triggers with the same parameter names can be distinguished
    """
    def cache_key(%PriceSettings{} = settings) do
      construct_cache_key([
        settings.type,
        settings.target,
        settings.time_window,
        settings.operation
      ])
    end

    defp payload(values, settings) do
      %{slug: slug, current: current, previous: previous, percent_change: percent_change} = values
      project = Sanbase.Model.Project.by_slug(slug)

      operation_text = if percent_change > 0, do: "moved up", else: "moved down"

      """
      **#{project.name}**'s price has #{operation_text} by **#{percent_change}%** from $#{
        round_price(previous)
      } to $#{round_price(current)} for the last #{interval_to_str(settings.time_window)}.
      More info here: #{Sanbase.Model.Project.sanbase_link(project)}
      ![Price chart over the past 90 days](#{chart_url(project, :volume)})
      """
    end
  end
end
