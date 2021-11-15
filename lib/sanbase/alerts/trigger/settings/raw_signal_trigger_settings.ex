defmodule Sanbase.Alert.Trigger.RawSignalTriggerSettings do
  @moduledoc ~s"""
  An alert based on the ClickHouse signals.

  The signal we're following is configured via the 'signal' parameter
  """

  use Vex.Struct

  import Sanbase.{Validation, Alert.Validation}
  import Sanbase.DateTimeUtils, only: [round_datetime: 1, str_to_sec: 1]

  alias __MODULE__
  alias Sanbase.Model.Project
  alias Sanbase.Alert.Type
  alias Sanbase.Cache
  alias Sanbase.Signal

  @derive {Jason.Encoder, except: [:filtered_target, :triggered?, :payload, :template_kv]}
  @trigger_type "raw_signal_data"

  @enforce_keys [:type, :channel, :operation]
  defstruct type: @trigger_type,
            signal: nil,
            channel: nil,
            selector: nil,
            target: nil,
            operation: nil,
            time_window: "1d",
            # Private fields, not stored in DB.
            filtered_target: %{list: []},
            triggered?: false,
            payload: %{},
            template_kv: %{}

  @type t :: %__MODULE__{
          signal: Type.signal(),
          type: Type.trigger_type(),
          channel: Type.channel(),
          target: nil | Type.complex_target(),
          selector: map(),
          operation: Type.operation(),
          time_window: Type.time_window(),
          # Private fields, not stored in DB.
          filtered_target: Type.filtered_target(),
          triggered?: boolean(),
          payload: Type.payload(),
          template_kv: Type.template_kv()
        }

  validates(:signal, &valid_signal?/1)
  validates(:operation, &valid_operation?/1)
  validates(:time_window, &valid_time_window?/1)

  @spec type() :: String.t()
  def type(), do: @trigger_type

  def post_create_process(_trigger), do: :nochange
  def post_update_process(_trigger), do: :nochange

  def new(settings) do
    struct(RawSignalTriggerSettings, settings)
  end

  def get_data(%{} = settings) do
    %{filtered_target: %{list: target_list, type: _type}} = settings

    {:ok, data} = fetch_signal(target_list, settings)

    target_list
    |> Enum.map(fn identifier ->
      {identifier, Enum.find(data, fn signal -> signal.slug == identifier end)}
    end)
    |> Enum.reject(fn {_, found} -> is_nil(found) end)
  end

  defp fetch_signal(slug_or_slugs, settings) do
    %{signal: signal, time_window: time_window} = settings

    cache_key =
      {__MODULE__, :fetch_raw_signal_data, signal, slug_or_slugs, time_window,
       round_datetime(Timex.now())}
      |> Sanbase.Cache.hash()

    %{from: from, to: to} = timerange_params(settings)

    Cache.get_or_store(cache_key, fn ->
      Signal.raw_data([signal], %{slug: slug_or_slugs}, from, to)
    end)
  end

  defp timerange_params(%RawSignalTriggerSettings{} = settings) do
    interval_seconds = str_to_sec(settings.time_window)
    now = Timex.now()

    %{
      from: Timex.shift(now, seconds: -interval_seconds),
      to: now
    }
  end

  defimpl Sanbase.Alert.Settings, for: RawSignalTriggerSettings do
    import Sanbase.Alert.Utils

    alias Sanbase.Alert.OperationText

    def triggered?(%RawSignalTriggerSettings{triggered?: triggered}), do: triggered

    def evaluate(%RawSignalTriggerSettings{} = settings, _trigger) do
      case RawSignalTriggerSettings.get_data(settings) do
        data when is_list(data) and data != [] ->
          build_result(data, settings)

        _ ->
          %RawSignalTriggerSettings{settings | triggered?: false}
      end
    end

    defp build_result(
           data,
           %RawSignalTriggerSettings{filtered_target: %{list: slugs}} = settings
         ) do
      template_kv =
        Enum.reduce(data, %{}, fn {slug, _}, acc ->
          if slug in slugs do
            Map.put(acc, slug, template_kv(settings, slug))
          else
            acc
          end
        end)

      case template_kv != %{} do
        true ->
          %RawSignalTriggerSettings{
            settings
            | triggered?: true,
              template_kv: template_kv
          }

        false ->
          %RawSignalTriggerSettings{settings | triggered?: false}
      end
    end

    def cache_key(%RawSignalTriggerSettings{} = settings) do
      construct_cache_key([
        settings.type,
        settings.target,
        settings.selector,
        settings.time_window,
        settings.operation
      ])
    end

    defp template_kv(settings, slug) do
      project = Project.by_slug(slug)

      {:ok, human_readable_name} = Sanbase.Signal.human_readable_name(settings.signal)

      {details_template, details_kv} = OperationText.details(:signal, settings)

      kv =
        %{
          type: settings.type,
          signal: settings.signal,
          project_name: project.name,
          project_slug: project.slug,
          project_ticker: project.ticker,
          signal_human_readable_name: human_readable_name
        }
        |> Map.merge(details_kv)

      template = """
      🔔 \#{{project_ticker}} | {{signal_human_readable_name}} signal fired for **{{project_name}}**.

      #{details_template}
      """

      {template, kv}
    end
  end
end
