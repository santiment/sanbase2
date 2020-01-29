defmodule Sanbase.Signal.Trigger.PriceAbsoluteChangeSettings do
  @moduledoc ~s"""
  PriceAbsoluteChangeSettings configures the settings for a signal that is fired
  when the price of `target` goes higher than `above` or lower than `below`
  """

  use Vex.Struct

  import Sanbase.Signal.Validation
  import Sanbase.Signal.{Utils, OperationEvaluation}

  alias __MODULE__
  alias Sanbase.Signal.Type

  alias Sanbase.Model.Project
  alias Sanbase.Signal.Evaluator.Cache

  @derive {Jason.Encoder, except: [:filtered_target, :triggered?, :payload, :template_kv]}
  @trigger_type "price_absolute_change"
  @enforce_keys [:type, :target, :channel]
  defstruct type: @trigger_type,
            target: nil,
            channel: nil,
            operation: %{},
            # Private fields, not stored in DB.
            filtered_target: %{list: []},
            triggered?: false,
            payload: %{},
            template_kv: %{}

  validates(:target, &valid_target?/1)
  validates(:channel, &valid_notification_channel?/1)
  validates(:operation, &valid_absolute_value_operation?/1)

  @type t :: %__MODULE__{
          type: Type.trigger_type(),
          target: Type.complex_target(),
          channel: Type.channel(),
          operation: Type.operation(),
          # Private fields, not stored in DB.
          filtered_target: Type.filtered_target(),
          triggered?: boolean(),
          payload: Type.payload(),
          template_kv: Type.template_kv()
        }

  @spec type() :: Type.trigger_type()
  def type(), do: @trigger_type

  def get_data(%__MODULE__{filtered_target: %{list: target_list}}) when is_list(target_list) do
    target_list
    |> Enum.map(fn slug ->
      {slug, get_data_by_slug(slug)}
    end)
  end

  defp get_data_by_slug(slug) when is_binary(slug) do
    Cache.get_or_store(
      {:last_usd_price, slug},
      fn ->
        now = Timex.now()
        yesterday = Timex.shift(now, hours: -3)

        # In case the last price is older than a few hours the result will be nil
        # and the signal won't be triggered.
        Sanbase.Price.aggregated_metric_timeseries_data(slug, :price_usd, yesterday, now,
          aggregation: :last
        )
        |> case do
          {:ok, %{^slug => price}} -> {:ok, price}
          error -> {:error, error}
        end
      end
    )
  end

  defimpl Sanbase.Signal.Settings, for: PriceAbsoluteChangeSettings do
    @doc ~s"""
    Construct a cache key only out of the parameters that determine the outcome.
    Parameters like `channel` are discarded. The `type` is included
    so different triggers with the same parameter names can be distinguished
    """

    alias Sanbase.Signal.OperationText

    def cache_key(%PriceAbsoluteChangeSettings{} = settings) do
      construct_cache_key([
        settings.type,
        settings.target,
        settings.operation
      ])
    end

    @spec triggered?(Sanbase.Signal.Trigger.PriceAbsoluteChangeSettings.t()) :: boolean()
    def triggered?(%PriceAbsoluteChangeSettings{triggered?: triggered}), do: triggered

    def evaluate(%PriceAbsoluteChangeSettings{} = settings, _trigger) do
      case PriceAbsoluteChangeSettings.get_data(settings) do
        list when is_list(list) and list != [] ->
          build_result(list, settings)

        _ ->
          %PriceAbsoluteChangeSettings{settings | triggered?: false}
      end
    end

    defp build_result(list, %PriceAbsoluteChangeSettings{operation: operation} = settings) do
      template_kv =
        Enum.reduce(list, %{}, fn {slug, {:ok, price}}, acc ->
          case operation_triggered?(price, operation) do
            true -> Map.put(acc, slug, template_kv(slug, price, operation))
            false -> acc
          end
        end)

      %PriceAbsoluteChangeSettings{
        settings
        | triggered?: template_kv != %{},
          template_kv: template_kv
      }
    end

    defp template_kv(slug, last_price_usd, operation) do
      project = Project.by_slug(slug)

      {operation_tempalte, template_kv} =
        OperationText.KV.to_template_kv(last_price_usd, operation)

      kv =
        %{
          project_name: project.name,
          project_link: Project.sanbase_link(project),
          project_chart: chart_url(project, :volume)
        }
        |> Map.merge(template_kv)

      template = """
      **{{project_name}}**'s price #{operation_tempalte}

      More information for the project you can find here: {{project_link}}

      ![Price chart over the past 90 days]({{project_chart}})
      """

      {template, kv}
    end
  end
end
