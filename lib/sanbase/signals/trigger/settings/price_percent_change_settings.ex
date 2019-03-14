defmodule Sanbase.Signals.Trigger.PricePercentChangeSettings do
  @moduledoc ~s"""
  PricePercentChangeSettings configures the settings for a signal that is fired
  when the price of `target` changes by more than `percent_threshold` percent for the
  specified `time_window` time.
  """
  use Vex.Struct
  import Sanbase.Signals.{Validation, Utils}

  alias __MODULE__
  alias Sanbase.Signals.Type
  alias Sanbase.Model.Project
  alias Sanbase.DateTimeUtils
  alias Sanbase.Signals.Evaluator.Cache

  @derive Jason.Encoder
  @trigger_type "price_percent_change"
  @enforce_keys [:type, :target, :channel, :time_window]
  defstruct type: @trigger_type,
            target: nil,
            filtered_target_list: [],
            channel: nil,
            time_window: nil,
            percent_threshold: nil,
            triggered?: false,
            payload: nil

  @type t :: %__MODULE__{
          type: Type.trigger_type(),
          target: Type.complex_target(),
          channel: Type.channel(),
          time_window: Type.time_window(),
          percent_threshold: number(),
          triggered?: boolean(),
          payload: Type.payload()
        }

  validates(:target, &valid_target?/1)
  validates(:channel, &valid_notification_channel/1)
  validates(:time_window, &valid_time_window?/1)
  validates(:percent_threshold, &valid_percent?/1)

  @spec type() :: Type.trigger_type()
  def type(), do: @trigger_type

  @spec get_data(__MODULE__.t()) :: list({Type.target(), any()})
  def get_data(%__MODULE__{filtered_target_list: target} = settings) when is_list(target) do
    time_window_sec = DateTimeUtils.compound_duration_to_seconds(settings.time_window)
    projects = Project.by_slugs(target)
    to = Timex.now()
    from = Timex.shift(to, seconds: -time_window_sec)

    projects
    |> Enum.map(&price_percent_change(&1, from, to))
  end

  defp price_percent_change(project, from, to) do
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
            {project.coinmarketcap_id,
             {:ok,
              {percent_change(first_usd_price, last_usd_price), first_usd_price, last_usd_price}}}

          error ->
            {project.coinmarketcap_id, {:error, error}}
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

    def evaluate(%PricePercentChangeSettings{} = settings) do
      case PricePercentChangeSettings.get_data(settings) do
        list when is_list(list) and list != [] ->
          build_result(list, settings)

        _ ->
          %PricePercentChangeSettings{settings | triggered?: false}
      end
    end

    defp build_result(
           list,
           %PricePercentChangeSettings{percent_threshold: percent_threshold} = settings
         ) do
      payload =
        Enum.reduce(list, %{}, fn
          {slug, {:ok, {percent_change, _, _} = price_data}}, acc
          when percent_change >= percent_threshold ->
            Map.put(acc, slug, payload(slug, settings, price_data))

          _, acc ->
            acc
        end)

      %PricePercentChangeSettings{
        settings
        | triggered?: payload != %{},
          payload: payload
      }
    end

    @doc ~s"""
    Construct a cache key only out of the parameters that determine the outcome.
    Parameters like `channel` are discarded. The `type` is included
    so different triggers with the same parameter names can be distinguished
    """
    def cache_key(%PricePercentChangeSettings{} = settings) do
      construct_cache_key([
        settings.type,
        settings.target,
        settings.time_window,
        settings.percent_threshold
      ])
    end

    defp payload(slug, settings, {percent_change, first_price, last_price}) do
      project = Sanbase.Model.Project.by_slug(slug)

      """
      **#{project.name}**'s price has changed by **#{percent_change}%** from $#{first_price} to $#{
        last_price
      } for the last #{DateTimeUtils.compound_duration_to_text(settings.time_window)}.
      More info here: #{Sanbase.Model.Project.sanbase_link(project)}
      ![Price chart over the past 90 days](#{chart_url(project, :volume)})
      """
    end
  end
end
