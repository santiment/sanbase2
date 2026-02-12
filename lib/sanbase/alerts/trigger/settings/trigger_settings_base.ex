defmodule Sanbase.Alert.Trigger.Settings.TriggerSettingsBase do
  @moduledoc """
  Provides common functionality shared across all trigger settings modules.

  Using this module injects:
  - `@behaviour Sanbase.Alert.Trigger.Settings.Behaviour`
  - `@derive {Jason.Encoder, ...}` excluding private fields
  - `@trigger_type` module attribute
  - `type/0` callback implementation
  - Default `post_create_process/1` and `post_update_process/1` (overridable)

  ## Usage

      use Sanbase.Alert.Trigger.Settings.TriggerSettingsBase, trigger_type: "my_trigger"

      @enforce_keys [:type, :channel]
      defstruct [
        type: @trigger_type,
        channel: nil
      ] ++ TriggerSettingsBase.private_struct_fields()
  """

  @private_struct_fields [
    filtered_target: %{list: []},
    triggered?: false,
    payload: %{},
    template_kv: %{}
  ]

  @doc "Returns the list of private struct fields common to all trigger settings."
  def private_struct_fields, do: @private_struct_fields

  defmacro __using__(opts) do
    trigger_type = Keyword.fetch!(opts, :trigger_type)

    quote do
      @behaviour Sanbase.Alert.Trigger.Settings.Behaviour
      @derive {Jason.Encoder, except: [:filtered_target, :triggered?, :payload, :template_kv]}
      @trigger_type unquote(trigger_type)

      alias Sanbase.Alert.Trigger.Settings.TriggerSettingsBase

      @spec type() :: String.t()
      def type(), do: @trigger_type

      def post_create_process(_trigger), do: :nochange
      def post_update_process(_trigger), do: :nochange

      defoverridable post_create_process: 1, post_update_process: 1
    end
  end

  @doc """
  Default evaluate implementation for trigger settings whose `get_data/1`
  returns `{:ok, list}` or `{:error, reason}`.

  Handles:
  - `{:ok, non_empty_list}` — calls the provided `build_result_fn`
  - `{:error, {:disable_alert, _}}` — propagates to auto-disable the alert
  - `{:error, reason}` — logs a warning, sets triggered? to false
  - anything else (e.g. `{:ok, []}`) — sets triggered? to false
  """
  require Logger

  def default_evaluate(module, settings, build_result_fn) do
    case module.get_data(settings) do
      {:ok, data} when is_list(data) and data != [] ->
        build_result_fn.(data)

      {:error, {:disable_alert, _}} = error ->
        error

      {:error, reason} ->
        Logger.warning("Error evaluating #{module.type()} alert: #{inspect(reason)}")
        {:ok, %{settings | triggered?: false}}

      _ ->
        {:ok, %{settings | triggered?: false}}
    end
  end
end
