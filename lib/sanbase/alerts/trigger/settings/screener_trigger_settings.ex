defmodule Sanbase.Alert.Trigger.ScreenerTriggerSettings do
  @moduledoc ~s"""
  An alert based on the screener feature.

  When a project fulfills the requirements of a given set of filters, an alert
  is fired that the project has entered the list. When a project no longer fulfills
  the filters, an alert is fired that the project exits the list.
  """
  @behaviour Sanbase.Alert.Trigger.Settings.Behaviour

  use Vex.Struct

  import Sanbase.Alert.Validation

  alias __MODULE__
  alias Sanbase.Alert.Type
  alias Sanbase.Model.Project

  @trigger_type "screener_signal"
  @derive {Jason.Encoder, except: [:filtered_target, :triggered?, :payload, :template_kv]}
  @enforce_keys [:type, :channel, :operation]

  defstruct type: @trigger_type,
            target: "default",
            channel: nil,
            operation: nil,
            # State keeps the list of assets the screener has had
            # during the last check. On every run the newly generated
            # list of assets is compared against the one stored in the
            # state. If there is a difference, the alert is triggered.
            state: %{},
            # Private fields, not stored
            filtered_target: %{list: []},
            triggered?: false,
            payload: %{},
            template_kv: %{}

  validates(:channel, &valid_notification_channel?/1)
  validates(:operation, &valid_operation?/1)

  @type t :: %__MODULE__{
          type: Type.trigger_type(),
          target: Type.target(),
          channel: Type.channel(),
          operation: Type.operation(),
          state: Map.t(),
          # Private fields, not stored in DB.
          filtered_target: Type.filtered_target(),
          triggered?: boolean(),
          payload: Type.payload(),
          template_kv: Type.template_kv()
        }

  @spec type() :: Type.trigger_type()
  def type(), do: @trigger_type

  def post_create_process(trigger), do: fill_current_state(trigger)
  def post_update_process(trigger), do: fill_current_state(trigger)

  @doc ~s"""
  Return a list of the `settings.metric` values for the necessary time range
  """
  @spec get_data(ScreenerTriggerSettings.t()) :: list(String.t())
  def get_data(%__MODULE__{operation: %{selector: %{watchlist_id: watchlist_id}}}) do
    {:ok, slugs} =
      case Sanbase.UserList.by_id(watchlist_id, []) do
        {:error, _} -> {:ok, []}
        {:ok, watchlist} -> watchlist |> Sanbase.UserList.get_slugs()
      end

    slugs
  end

  def get_data(%__MODULE__{operation: %{selector: _} = selector}) do
    {:ok, %{slugs: slugs}} = Project.ListSelector.slugs(selector)

    slugs
  end

  defp fill_current_state(trigger) do
    %{settings: settings} = trigger
    slugs = get_data(settings)
    settings = %{settings | state: %{slugs_in_screener: slugs}}

    %{trigger | settings: settings}
  end

  defimpl Sanbase.Alert.Settings, for: ScreenerTriggerSettings do
    alias Sanbase.Alert.Trigger.ScreenerTriggerSettings
    alias Sanbase.Alert.ResultBuilder

    def triggered?(%ScreenerTriggerSettings{triggered?: triggered}), do: triggered

    @spec evaluate(ScreenerTriggerSettings.t(), any) :: ScreenerTriggerSettings.t()
    def evaluate(%ScreenerTriggerSettings{} = settings, trigger) do
      case ScreenerTriggerSettings.get_data(settings) do
        data when is_list(data) and data != [] ->
          build_result(data, settings, trigger)

        _ ->
          %ScreenerTriggerSettings{settings | triggered?: false}
      end
    end

    def build_result(current_slugs, settings, trigger) do
      # The ResultBuilder expects a 2-arity function, so we bind the
      # third `trigger` argument and make it a 2-arity function
      template_kv_fun = &template_kv(&1, &2, trigger)

      ResultBuilder.build_state_difference(current_slugs, settings, template_kv_fun,
        state_list_key: :slugs_in_screener,
        added_items_key: :added_slugs,
        removed_items_key: :removed_slugs
      )
    end

    def cache_key(%ScreenerTriggerSettings{}) do
      # The result heavily depends on the trigger state
      :nocache
    end

    defp template_kv(values, settings, trigger) do
      %{added_slugs: added_slugs, removed_slugs: removed_slugs} = values

      kv = %{
        type: ScreenerTriggerSettings.type(),
        operation: settings.operation,
        added_slugs: added_slugs,
        removed_slugs: removed_slugs
      }

      template = """
      🔔 Screener "#{trigger.title}" changes:
      #{ResultBuilder.build_enter_exit_projects_str(added_slugs, removed_slugs)}
      """

      {template, kv}
    end
  end
end
