defmodule Sanbase.Signals.Trigger.PriceVolumeTriggerSettings do
  use Vex.Struct

  import Sanbase.Signals.Validation

  alias __MODULE__
  alias Sanbase.Model.Project
  alias Sanbase.TechIndicators.PriceVolumeDifference

  @derive Jason.Encoder
  @trigger_type "price_volume"
  @enforce_keys [:type, :target, :channel, :time_window, :threhsold]

  defstruct type: @trigger_type,
            target: nil,
            channel: nil,
            time_window: nil,
            threhsold: nil,
            aggregate_interval: nil,
            window_type: nil,
            approximation_window: nil,
            comparison_window: nil,
            repeating: false,
            triggered?: false,
            payload: nil

  validates(:target, &valid_target?/1)
  validates(:channel, &valid_notification_channel/1)
  validates(:threhsold, &valid_threhsold?/1)
  validates(:time_window, &valid_time_window?/1)
  validates(:repeating, &is_boolean/1)

  @typedoc ~s"""
  threhsold -
  aggregate_interval -
  window_type - Window type for calculating window weights.
    See https://docs.scipy.org/doc/scipy/reference/signal.html#window-functions
  approximation_window - Window for calculating the moving average for a point
    in number of data points.
  comparison_window - window used for calculating the previous data using MA for
    a data point. It is used for calculating increase/decrease in values in number
    of data points.
  """
  @type t :: %__MODULE__{
          type: Type.trigger_type(),
          target: Type.complex_target(),
          channel: Type.channel(),
          time_window: Type.time_window(),
          threhsold: Type.threhsold(),
          aggregate_interval: Type.time(),
          window_type: nil,
          approximation_window: nil,
          comparison_window: nil,
          triggered?: boolean(),
          payload: Type.payload()
        }

  @spec type() :: Type.trigger_type()
  def type(), do: @trigger_type

  def get_data(%{target: target} = settings) when is_list(target) do
    target
    |> Enum.map(fn slug -> get_data_for_single_project(slug, settings) end)
  end

  defp get_data_for_single_project(slug, settings) do
    project = Projext.by_slug(slug)

    result =
      PriceVolumeDifference.price_volume_diff(
        project,
        "USD",
        Timex.shift(Timex.now(),
          seconds: -Sanbase.DateTimeUtils.compound_duration_to_seconds(settings.time_window)
        ),
        Timex.now(),
        settings.aggregate_interval,
        settings.window_type,
        settings.approximation_window,
        settings.comparison_window
      )

    {slug, result}
  end

  defimpl Sanbase.Signals.Settings, for: PriceVolumeTriggerSettings do
    def triggered?(%PriceVolumeTriggerSettings{triggered?: triggered}), do: triggered

    def evaluate(%PriceVolumeTriggerSettings{} = settings) do
      case PriceVolumeTriggerSettings.get_data(settings) do
        list when is_list(list) and list != [] ->
          build_result(list, settings)

        _ ->
          %PriceVolumeTriggerSettings{settings | triggered?: false}
      end
    end

    defp build_result(
           list,
           %PriceVolumeTriggerSettings{threhsold: threhsold} = settings
         ) do
      payload =
        Enum.reduce(list, %{}, fn
          {slug, {:ok, %{price_volume_diff: price_volume_diff}}}, acc
          when price_volume_diff >= threhsold ->
            Map.put(acc, slug, payload(slug, settings, price_volume_diff))

          _, acc ->
            acc
        end)

      %PriceVolumeTriggerSettings{
        settings
        | triggered?: payload != %{},
          payload: payload
      }
    end

    defp payload(slug, settings, price_volume_diff) do
      project = Sanbase.Model.Project.by_slug(slug)

      """
      The price and volume of **#{project.name}** have diverged over the threshold of #{
        settings.threhsold
      }. Current value: **#{price_volume_diff}**

      More info here: #{Sanbase.Model.Project.sanbase_link(project)}
      ![PriceVolume chart over the past 90 days](#{chart_url(project)})
      """
    end

    defp chart_url(project) do
      Sanbase.Chart.build_embedded_chart(
        project,
        Timex.shift(Timex.now(), days: -90),
        Timex.now(),
        chart_type: :price_volume
      )
      |> case do
        [%{image: %{url: chart_url}}] -> chart_url
        _ -> nil
      end
    end
  end
end
