defprotocol Sanbase.Signals.Settings do
  def evaluate(trigger_settings, trigger)

  @spec triggered?(struct()) :: boolean()
  def triggered?(trigger)

  @spec cache_key(struct()) :: String.t() | :nocache
  def cache_key(trigger)
end

defprotocol Sanbase.Signals.History do
  @spec historical_trigger_points(struct(), String.t()) :: {:ok, list(any())} | {:error, any()}
  def historical_trigger_points(trigger, cooldown)
end

defmodule Sanbase.Signals.Trigger do
  @moduledoc ~s"""
  Module that represents an embedded schema that is used in UserTrigger`s `jsonb`
  column. It represents a trigger, providing some common fields:
    - `is_public` - boolean, indicating if other people can see that trigger
    - `last_triggered` - the last datetime when it was triggered
    - `cooldown` - after how long the trigger can be triggered and sent again.
    - `settings` field is a map that gets converted to one of the available
  TriggerSettings modules. They implement a protocol that allows the evaluator
  to easily process them.
  """
  use Ecto.Schema
  use Vex.Struct
  import Ecto.Changeset

  alias __MODULE__
  alias Sanbase.Model.Project
  alias Sanbase.DateTimeUtils

  embedded_schema do
    field(:settings, :map)
    field(:title, :string)
    field(:description, :string)
    field(:is_public, :boolean, default: false)
    field(:last_triggered, :map, default: %{})
    field(:cooldown, :string, default: "24h")
    field(:icon_url, :string)
    field(:is_active, :boolean, default: true)
    field(:is_repeating, :boolean, default: true)
  end

  @type t :: %__MODULE__{
          settings: map() | struct(),
          is_public: boolean(),
          cooldown: String.t(),
          last_triggered: map(),
          title: String.t(),
          description: String.t(),
          icon_url: String.t(),
          is_active: boolean(),
          is_repeating: boolean()
        }

  @doc false
  @fields [
    :settings,
    :is_public,
    :cooldown,
    :last_triggered,
    :title,
    :description,
    :icon_url,
    :is_active,
    :is_repeating
  ]

  def create_changeset(%__MODULE__{} = trigger, args \\ %{}) do
    trigger
    |> cast(args, @fields)
    |> validate_required([:settings, :title])
    |> validate_change(:icon_url, &validate_url/2)
  end

  def update_changeset(%__MODULE__{} = trigger, args \\ %{}) do
    trigger
    |> cast(args, @fields)
    |> validate_change(:icon_url, &validate_url/2)
  end

  defp validate_url(_changeset, url) do
    case Sanbase.Signals.Validation.valid_url?(url) do
      :ok -> []
      {:error, reason} -> [icon_url: reason]
    end
  end

  def evaluate(%Trigger{settings: %{target: target} = trigger_settings} = trigger) do
    trigger_settings =
      %{trigger_settings | filtered_target: remove_targets_on_cooldown(target, trigger)}
      |> Sanbase.Signals.Settings.evaluate(trigger)

    %Trigger{trigger | settings: trigger_settings}
  end

  def historical_trigger_points(%Trigger{settings: trigger_settings, cooldown: cooldown}) do
    Sanbase.Signals.History.historical_trigger_points(trigger_settings, cooldown)
  end

  def triggered?(%Trigger{settings: trigger_settings}) do
    Sanbase.Signals.Settings.triggered?(trigger_settings)
  end

  def cache_key(%Trigger{settings: trigger_settings}) do
    Sanbase.Signals.Settings.cache_key(trigger_settings)
  end

  def last_triggered(%Trigger{last_triggered: lt}, _target) when map_size(lt) == 0, do: nil

  def last_triggered(%Trigger{last_triggered: lt}, target) do
    Map.get(lt, target)
  end

  def has_cooldown?(%Trigger{} = trigger, target) do
    case last_triggered(trigger, target) do
      nil ->
        false

      target_last_triggered ->
        target_last_triggered = target_last_triggered |> DateTimeUtils.from_iso8601!()

        Timex.compare(
          DateTimeUtils.after_interval(trigger.cooldown, target_last_triggered),
          Timex.now()
        ) == 1
    end
  end

  def human_readable_settings_type(type) do
    type
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp remove_targets_on_cooldown(target, trigger) when is_binary(target) or is_list(target) do
    target
    |> List.wrap()
    |> remove_targets_on_cooldown(trigger, :slug)
  end

  defp remove_targets_on_cooldown(%{user_list: user_list_id}, trigger) do
    %{list_items: list_items} = Sanbase.UserList.by_id(user_list_id)

    list_items
    |> Enum.map(fn %{project_id: id} -> id end)
    |> Project.List.slugs_by_ids()
    |> remove_targets_on_cooldown(trigger, :slug)
  end

  defp remove_targets_on_cooldown(%{slug: slug}, trigger)
       when is_binary(slug) or is_list(slug) do
    slug
    |> List.wrap()
    |> remove_targets_on_cooldown(trigger, :slug)
  end

  defp remove_targets_on_cooldown(%{eth_address: address}, trigger)
       when is_binary(address) or is_list(address) do
    address
    |> List.wrap()
    |> remove_targets_on_cooldown(trigger, :eth_address)
  end

  defp remove_targets_on_cooldown(target_list, trigger, type) when is_list(target_list) do
    target_list =
      target_list
      |> Enum.reject(&Sanbase.Signals.Trigger.has_cooldown?(trigger, &1))

    %{list: target_list, type: type}
  end
end
