defmodule Sanbase.Signal.Trigger.PricePercentChangeSettings do
  @moduledoc ~s"""
  PricePercentChangeSettings configures the settings for a signal that is fired
  when the price of `target` moves up or down by specified percent for the
  specified `time_window` time.
  """
  use Vex.Struct

  import Sanbase.{Validation, Signal.Validation}
  import Sanbase.Signal.{Utils, OperationEvaluation}
  import Sanbase.Math, only: [percent_change: 2]
  import Sanbase.DateTimeUtils, only: [str_to_sec: 1, round_datetime: 2]

  alias __MODULE__
  alias Sanbase.Signal.Type
  alias Sanbase.Model.Project
  alias Sanbase.Signal.Evaluator.Cache

  @derive {Jason.Encoder, except: [:filtered_target, :triggered?, :payload, :template_kv]}
  @trigger_type "price_percent_change"
  @enforce_keys [:type, :target, :channel, :time_window]
  defstruct type: @trigger_type,
            target: nil,
            channel: nil,
            time_window: nil,
            operation: %{},
            # Private fields, not stored in DB.
            filtered_target: %{list: []},
            triggered?: false,
            payload: %{},
            template_kv: %{}

  @type t :: %__MODULE__{
          type: Type.trigger_type(),
          target: Type.complex_target(),
          channel: Type.channel(),
          time_window: Type.time_window(),
          operation: Type.operation(),
          # Private fields, not stored in DB.
          filtered_target: Type.filtered_target(),
          triggered?: boolean(),
          payload: Type.payload(),
          template_kv: Type.template_kv()
        }

  validates(:target, &valid_target?/1)
  validates(:channel, &valid_notification_channel?/1)
  validates(:time_window, &valid_time_window?/1)
  validates(:operation, &valid_percent_change_operation?/1)

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
    |> Enum.map(&price_percent_change(&1, from, to))
  end

  defp price_percent_change(project, from, to) do
    cache_key =
      {:price_percent_signal, project.slug, round_datetime(from, 300), round_datetime(to, 300)}
      |> Sanbase.Cache.hash()

    Cache.get_or_store(
      cache_key,
      fn ->
        case Sanbase.Price.ohlc(project.slug, from, to) do
          {:ok, %{open_price_usd: open, close_price_usd: close}} ->
            {project.slug, {:ok, {percent_change(open, close), open, close}}}

          {:error, error} ->
            {project.slug, {:error, error}}
        end
      end
    )
  end

  defimpl Sanbase.Signal.Settings, for: PricePercentChangeSettings do
    alias Sanbase.Signal.OperationText

    def triggered?(%PricePercentChangeSettings{triggered?: triggered}), do: triggered

    def evaluate(%PricePercentChangeSettings{} = settings, _trigger) do
      case PricePercentChangeSettings.get_data(settings) do
        list when is_list(list) and list != [] ->
          build_result(list, settings)

        _ ->
          %PricePercentChangeSettings{settings | triggered?: false}
      end
    end

    defp build_result(
           list,
           %PricePercentChangeSettings{operation: operation} = settings
         ) do
      template_kv =
        Enum.reduce(list, %{}, fn
          {slug, {:ok, {percent_change, _, _} = price_data}}, acc ->
            case operation_triggered?(percent_change, operation) do
              true -> Map.put(acc, slug, template_kv(slug, settings, price_data))
              false -> acc
            end

          _, acc ->
            acc
        end)

      %PricePercentChangeSettings{
        settings
        | triggered?: template_kv != %{},
          template_kv: template_kv
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
        settings.operation
      ])
    end

    defp template_kv(slug, settings, {percent_change, first_price, last_price}) do
      project = Project.by_slug(slug)
      last_price = Sanbase.Signal.Utils.round_price(last_price)

      {operation_template, operation_kv} =
        OperationText.to_template_kv(percent_change, settings.operation)

      {curr_value_template, curr_value_kv} =
        OperationText.current_value(%{current: last_price}, settings.operation)

      kv =
        %{
          type: PricePercentChangeSettings.type(),
          operation: settings.operation,
          project_name: project.name,
          project_slug: project.slug,
          previous_value: round_price(first_price),
          value: round_price(last_price),
          chart_url: chart_url(project, :volume)
        }
        |> Map.merge(operation_kv)
        |> Map.merge(curr_value_kv)

      template = """
      **{{project_name}}**'s price #{operation_template} and #{curr_value_template}

      More info here: #{Project.sanbase_link(project)}
      ![Price chart over the past 90 days]({{chart_url}})
      """

      {template, kv}
    end
  end
end
