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
            state: nil,
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
      %{state: %{slugs_in_screener: previous_slugs}} = settings
      added_slugs = (current_slugs -- previous_slugs) |> Enum.reject(&is_nil/1)
      removed_slugs = (previous_slugs -- current_slugs) |> Enum.reject(&is_nil/1)

      case added_slugs != [] or removed_slugs != [] do
        true ->
          template_kv =
            template_kv(
              %{added_slugs: added_slugs, removed_slugs: removed_slugs},
              settings,
              trigger
            )

          %ScreenerTriggerSettings{
            settings
            | template_kv: %{"default" => template_kv},
              state: %{slugs_in_screener: current_slugs},
              triggered?: true
          }

        false ->
          %ScreenerTriggerSettings{settings | triggered?: false}
      end
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
      🔔Screener "#{trigger.title}" changes:
      #{format_enter_exit_slugs(added_slugs, removed_slugs)}
      """

      {template, kv}
    end

    defp format_enter_exit_slugs(added_slugs, removed_slugs) do
      projects_map =
        Project.List.by_slugs(added_slugs ++ removed_slugs, preload?: false)
        |> Enum.into(%{}, fn %{slug: slug} = project -> {slug, project} end)

      newcomers = slugs_to_projects_string_list(added_slugs, projects_map)
      leavers = slugs_to_projects_string_list(removed_slugs, projects_map)

      """
      #{length(newcomers)} Newcomers:
      #{newcomers |> Enum.join("\n")}
      ---
      #{length(leavers)} Leavers:
      #{leavers |> Enum.join("\n")}
      """
    end

    defp slugs_to_projects_string_list(slugs, projects_map) do
      slugs
      |> Enum.map(&Map.get(projects_map, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&"[##{&1.ticker} | #{&1.name}](#{Project.sanbase_link(&1)})")
    end
  end
end
