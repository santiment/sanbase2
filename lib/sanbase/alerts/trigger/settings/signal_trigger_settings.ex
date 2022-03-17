defmodule Sanbase.Alert.Trigger.SignalTriggerSettings do
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
  @trigger_type "signal_data"

  @enforce_keys [:type, :channel, :target]
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
          target: Type.complex_target(),
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

  def get_data(%{} = settings) do
    %{filtered_target: %{list: target_list, type: type}} = settings

    target_list
    |> Enum.map(fn identifier ->
      {identifier, fetch_signal(%{type => identifier}, settings)}
    end)
    |> Enum.reject(fn
      {_, {:error, _}} -> true
      {_, nil} -> true
      _ -> false
    end)
  end

  defp fetch_signal(selector, settings) do
    %{signal: signal, time_window: time_window} = settings

    cache_key =
      {__MODULE__, :fetch_signal_data, signal, selector, time_window, round_datetime(Timex.now())}
      |> Sanbase.Cache.hash()

    %{
      first_start: first_start,
      first_end: first_end,
      second_start: second_start,
      second_end: second_end
    } = timerange_params(settings)

    slug = selector.slug

    Cache.get_or_store(cache_key, fn ->
      with {:ok, %{^slug => value1}} <-
             Signal.aggregated_timeseries_data(signal, selector, first_start, first_end, []),
           {:ok, %{^slug => value2}} <-
             Signal.aggregated_timeseries_data(signal, selector, second_start, second_end, []) do
        [
          %{datetime: first_start, value: value1},
          %{datetime: second_start, value: value2}
        ]
      else
        _ -> {:error, "Cannot fetch #{signal} for #{inspect(selector)}"}
      end
    end)
  end

  defp timerange_params(%SignalTriggerSettings{} = settings) do
    interval_seconds = str_to_sec(settings.time_window)
    now = Timex.now()

    %{
      first_start: Timex.shift(now, seconds: -2 * interval_seconds),
      first_end: Timex.shift(now, seconds: -interval_seconds),
      second_start: Timex.shift(now, seconds: -interval_seconds),
      second_end: now
    }
  end

  defimpl Sanbase.Alert.Settings, for: SignalTriggerSettings do
    import Sanbase.Alert.Utils

    alias Sanbase.Alert.{OperationText, ResultBuilder}

    def triggered?(%SignalTriggerSettings{triggered?: triggered}), do: triggered

    def evaluate(%SignalTriggerSettings{} = settings, _trigger) do
      case SignalTriggerSettings.get_data(settings) do
        data when is_list(data) and data != [] ->
          build_result(data, settings)

        _ ->
          %SignalTriggerSettings{settings | triggered?: false}
      end
    end

    def build_result(data, %SignalTriggerSettings{} = settings) do
      ResultBuilder.build(data, settings, &template_kv/2)
    end

    def cache_key(%SignalTriggerSettings{} = settings) do
      construct_cache_key([
        settings.type,
        settings.target,
        settings.selector,
        settings.time_window,
        settings.operation
      ])
    end

    defp template_kv(values, settings) do
      %{identifier: slug} = values
      project = Project.by_slug(slug)

      {operation_template, operation_kv} =
        OperationText.to_template_kv(values, settings.operation)

      {:ok, human_readable_name} = Sanbase.Signal.human_readable_name(settings.signal)

      {curr_value_template, curr_value_kv} = OperationText.current_value(values)

      {details_template, details_kv} = OperationText.details(:signal, settings)

      kv =
        %{
          type: settings.type,
          operation: settings.operation,
          signal: settings.signal,
          project_name: project.name,
          project_slug: project.slug,
          project_ticker: project.ticker,
          signal_human_readable_name: human_readable_name
        }
        |> OperationText.merge_kvs(operation_kv)
        |> OperationText.merge_kvs(curr_value_kv)
        |> OperationText.merge_kvs(details_kv)

      template = """
      🔔 \#{{project_ticker}} | **{{project_name}}**'s {{signal_human_readable_name}} #{operation_template}.
      #{curr_value_template}.

      #{details_template}
      """

      {template, kv}
    end
  end
end
