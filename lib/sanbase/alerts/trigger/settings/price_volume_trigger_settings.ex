defmodule Sanbase.Alert.Trigger.PriceVolumeDifferenceTriggerSettings do
  @behaviour Sanbase.Alert.Trigger.Settings.Behaviour

  use Vex.Struct

  import Sanbase.{Validation, Alert.Validation}
  import Sanbase.Alert.Utils

  alias __MODULE__
  alias Sanbase.Alert.Type
  alias Sanbase.Model.Project
  alias Sanbase.TechIndicators.PriceVolumeDifference

  @derive {Jason.Encoder, except: [:filtered_target, :triggered?, :payload, :template_kv]}
  @trigger_type "price_volume_difference"
  @enforce_keys [:type, :target, :channel, :threshold]

  defstruct type: @trigger_type,
            target: nil,
            channel: nil,
            threshold: 0.002,
            aggregate_interval: "1d",
            window_type: "bohman",
            approximation_window: 14,
            comparison_window: 7,
            # Private fields, not stored in DB.
            filtered_target: %{list: []},
            triggered?: false,
            payload: %{},
            template_kv: %{}

  validates(:target, &valid_target?/1)
  validates(:channel, &valid_notification_channel?/1)
  validates(:threshold, &valid_threshold?/1)

  @type window_type :: String.t()
  @type approximation_window :: non_neg_integer()
  @type comparison_window :: non_neg_integer()

  @typedoc ~s"""
  threshold - the sensitivity of the trigger. Defaults to 0.002
  aggregate_interval - The interval at which the price and volume are aggregated.
    Defaults to 1d
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
          threshold: Type.threshold(),
          aggregate_interval: Type.time(),
          window_type: window_type(),
          approximation_window: approximation_window(),
          comparison_window: comparison_window(),
          # Private fields, not stored in DB.
          filtered_target: Type.filtered_target(),
          triggered?: boolean(),
          payload: Type.payload(),
          template_kv: Type.template_kv()
        }

  @spec type() :: Type.trigger_type()
  def type(), do: @trigger_type

  def post_create_process(_trigger), do: :nochange
  def post_update_process(_trigger), do: :nochange

  def get_data(%__MODULE__{filtered_target: %{list: target_list}} = settings)
      when is_list(target_list) do
    target_list
    |> Enum.map(fn slug -> get_data_for_single_project(slug, settings) end)
  end

  def get_data_for_single_project(slug, settings) when is_binary(slug) do
    project = Project.by_slug(slug)

    # return only the last result
    result =
      PriceVolumeDifference.price_volume_diff(
        project,
        "USD",
        Timex.shift(Timex.now(), days: -14),
        Timex.now(),
        settings.aggregate_interval,
        settings.window_type,
        settings.approximation_window,
        settings.comparison_window,
        1
      )
      |> case do
        {:ok, result} -> {:ok, result |> List.first()}
        error -> error
      end

    {slug, result}
  end

  defimpl Sanbase.Alert.Settings, for: PriceVolumeDifferenceTriggerSettings do
    def triggered?(%PriceVolumeDifferenceTriggerSettings{triggered?: triggered}), do: triggered

    def evaluate(%PriceVolumeDifferenceTriggerSettings{} = settings, _trigger) do
      case PriceVolumeDifferenceTriggerSettings.get_data(settings) do
        list when is_list(list) and list != [] ->
          build_result(list, settings)

        _ ->
          %PriceVolumeDifferenceTriggerSettings{settings | triggered?: false}
      end
    end

    def cache_key(%PriceVolumeDifferenceTriggerSettings{} = settings) do
      construct_cache_key([
        settings.threshold,
        settings.aggregate_interval,
        settings.window_type,
        settings.approximation_window,
        settings.comparison_window
      ])
    end

    defp build_result(
           list,
           %PriceVolumeDifferenceTriggerSettings{threshold: threshold} = settings
         ) do
      template_kv =
        Enum.reduce(list, %{}, fn
          {slug, {:ok, %{price_volume_diff: price_volume_diff}}}, acc
          when price_volume_diff >= threshold ->
            Map.put(acc, slug, template_kv(slug, settings, price_volume_diff))

          _, acc ->
            acc
        end)

      %PriceVolumeDifferenceTriggerSettings{
        settings
        | triggered?: template_kv != %{},
          template_kv: template_kv
      }
    end

    defp template_kv(slug, settings, price_volume_diff) do
      project = Sanbase.Model.Project.by_slug(slug)

      kv = %{
        type: PriceVolumeDifferenceTriggerSettings.type(),
        threhsold: settings.threshold,
        project_name: project.name,
        project_ticker: project.ticker,
        project_slug: project.slug,
        value: price_volume_diff
      }

      template = """
      🔔 \#{{project_ticker}} | **{{project_name}}**'s price and trading volume have diverged.
      The price is increasing while the volume is decreasing.
      """

      {template, kv}
    end
  end
end
