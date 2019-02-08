defmodule Sanbase.Signals.Trigger.PricePercentChangeSettings do
  @moduledoc ~s"""
  PricePercentChangeSettings configures the settings for a signal that is fired
  when the price of `target` changes by more than `percent_threshold` percent for the
  specified `time_window` time.
  """

  @derive Jason.Encoder
  @trigger_type "price_percent_change"
  @enforce_keys [:type, :target, :channel, :time_window]
  defstruct type: @trigger_type,
            target: nil,
            channel: nil,
            time_window: nil,
            percent_threshold: nil,
            repeating: false,
            triggered?: false,
            payload: nil

  alias Sanbase.Signals.Type

  @type t :: %__MODULE__{
          type: Type.trigger_type(),
          target: Type.target(),
          channel: Type.channel(),
          time_window: Type.time_window(),
          percent_threshold: number(),
          repeating: boolean(),
          triggered?: boolean(),
          payload: Type.payload()
        }
  use Vex.Struct
  import Sanbase.Signals.Utils

  alias __MODULE__
  alias Sanbase.Model.Project
  alias Sanbase.Signals.Evaluator.Cache

  validates(:channel, inclusion: notification_channels)

  def type(), do: @trigger_type

  def get_data(settings) do
    time_window_sec = Sanbase.DateTimeUtils.compound_duration_to_seconds(settings.time_window)
    project = Project.by_slug(settings.target)
    to = Timex.now()
    from = Timex.shift(to, seconds: -time_window_sec)

    Cache.get_or_store(
      cache_key_datetimes(project, from, to),
      fn ->
        Sanbase.Prices.Store.first_last_price(
          Sanbase.Influxdb.Measurement.name_from(project),
          from,
          to
        )
        |> case do
          {:ok, [[_dt, first_usd_price, last_usd_price]]} ->
            {:ok, Sanbase.Signals.Utils.percent_change(first_usd_price, last_usd_price)}

          error ->
            {:error, error}
        end
      end
    )
  end

  defp cache_key_datetimes(project, from, to) do
    # prices are present at 5 minute intervals
    from_rounded = div(DateTime.to_unix(from, :second), 300) * 300
    to_rounded = div(DateTime.to_unix(to, :second), 300) * 300

    "first_last_#{project.id}_#{from_rounded}_#{to_rounded}"
  end

  defimpl Sanbase.Signals.Settings, for: PricePercentChangeSettings do
    def triggered?(%PricePercentChangeSettings{triggered?: triggered}), do: triggered

    def evaluate(%PricePercentChangeSettings{percent_threshold: percent_threshold} = settings) do
      case PricePercentChangeSettings.get_data(settings) do
        {:ok, percent_change} when percent_change >= percent_threshold ->
          %PricePercentChangeSettings{
            settings
            | triggered?: true,
              payload: payload(settings, percent_change)
          }

        _ ->
          %PricePercentChangeSettings{settings | triggered?: false}
      end
    end

    @doc ~s"""
    Construct a cache key only out of the parameters that determine the outcome.
    Parameters like `repeating` and `channel` are discarded. The `type` is included
    so different triggers with the same parameter names can be distinguished
    """
    def cache_key(%PricePercentChangeSettings{} = settings) do
      data =
        [
          settings.type,
          settings.target,
          settings.time_window,
          settings.percent_threshold
        ]
        |> Jason.encode!()

      :crypto.hash(:sha256, data)
      |> Base.encode16()
    end

    defp chart_url(project) do
      Sanbase.Chart.build_embedded_chart(
        project,
        Timex.shift(Timex.now(), days: -90),
        Timex.now()
      )
      |> case do
        [%{image: %{url: chart_url}}] -> chart_url
        _ -> nil
      end
    end

    defp payload(settings, percent_change) do
      project = Sanbase.Model.Project.by_slug(settings.target)

      """
      The price of **#{project.name}** has changed by **#{percent_change}%** for the last #{
        Sanbase.DateTimeUtils.compound_duration_to_text(settings.time_window)
      }.
      More info here: #{Sanbase.Model.Project.sanbase_link(project)}
      ![Price chart over the past 90 days](#{chart_url(project)})
      """
    end
  end
end
