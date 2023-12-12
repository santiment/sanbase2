defprotocol Sanbase.Alert.Settings do
  @moduledoc ~s"""
  A protocol that must be implemented by all trigger settings.

  Every trigger has settings that define how it is evaluated, how it's cached
  and how to check if the evaluated alert is triggered.

  After creating the module 3 things should be done in order to run the signal:
  - Add a map between the StructMapTransformation
  """

  @spec evaluate(map(), map()) :: {:ok, map} | {:error, any()}
  def evaluate(trigger_settings, trigger)

  @spec triggered?(struct()) :: boolean()
  def triggered?(trigger)

  @spec cache_key(struct()) :: String.t() | :nocache
  def cache_key(trigger)
end

defprotocol Sanbase.Alert.History do
  @spec historical_trigger_points(struct(), String.t()) :: {:ok, list(any())} | {:error, any()}
  def historical_trigger_points(trigger, cooldown)
end

defmodule Sanbase.Alert.Trigger do
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
  alias Sanbase.DateTimeUtils

  embedded_schema do
    field(:settings, :map)
    field(:is_frozen, :boolean, default: false)
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
    :is_frozen,
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

  defp validate_url(:icon_url, url) do
    case Sanbase.Validation.valid_url?(url) do
      :ok -> []
      {:error, reason} -> [icon_url: reason]
    end
  end

  def payload_to_string(%Trigger{settings: %{payload: {template, kv}}}) do
    Sanbase.TemplateEngine.run!(template, params: kv)
  end

  def payload_to_string({template, kv}) do
    Sanbase.TemplateEngine.run!(template, params: kv)
  end

  def get_filtered_target(%Trigger{settings: %{target: target}} = trigger) do
    remove_targets_on_cooldown(target, trigger)
  end

  def evaluate(%Trigger{settings: %{target: target} = trigger_settings} = trigger) do
    filtered_target = remove_targets_on_cooldown(target, trigger)
    trigger_settings = %{trigger_settings | filtered_target: filtered_target}

    case Sanbase.Alert.Settings.evaluate(trigger_settings, trigger) do
      {:ok, trigger_settings} ->
        trigger = %Trigger{trigger | settings: trigger_settings}
        {:ok, trigger}

      {:error, error} ->
        {:error, error}
    end
  end

  @spec historical_trigger_points(Sanbase.Alert.Trigger.t()) :: {:error, any} | {:ok, [any]}
  def historical_trigger_points(%Trigger{settings: trigger_settings, cooldown: cooldown}) do
    Sanbase.Alert.History.historical_trigger_points(trigger_settings, cooldown)
  end

  def triggered?(%Trigger{settings: trigger_settings}) do
    Sanbase.Alert.Settings.triggered?(trigger_settings)
  end

  def cache_key(%Trigger{settings: trigger_settings}) do
    Sanbase.Alert.Settings.cache_key(trigger_settings)
  end

  def last_triggered(%Trigger{last_triggered: lt}, _target) when map_size(lt) == 0, do: nil

  def last_triggered(%Trigger{last_triggered: lt}, target) do
    case Map.get(lt, target) do
      nil -> nil
      last_triggered -> last_triggered |> DateTimeUtils.from_iso8601!()
    end
  end

  def has_cooldown?(%Trigger{} = trigger, target) do
    case last_triggered(trigger, target) do
      nil ->
        false

      %DateTime{} = target_last_triggered ->
        DateTime.compare(
          DateTimeUtils.after_interval(trigger.cooldown, target_last_triggered),
          Timex.now()
        ) == :gt
    end
  end

  def human_readable_settings_type(type) do
    type
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp remove_targets_on_cooldown(%{user_list: user_list_id}, trigger) do
    remove_targets_on_cooldown(%{watchlist_id: user_list_id}, trigger)
  end

  defp remove_targets_on_cooldown(%{watchlist_id: watchlist_id}, trigger) do
    case Sanbase.UserList.by_id(watchlist_id, []) do
      {:error, _} ->
        %{list: [], type: :slug}

      {:ok, watchlist} ->
        case Sanbase.UserList.get_projects(watchlist) do
          {:ok, %{projects: projects}} ->
            projects
            |> Enum.map(& &1.slug)
            |> remove_targets_on_cooldown(trigger, :slug)

          {:error, _error} ->
            []
        end
    end
  end

  defp remove_targets_on_cooldown(%{market_segments: market_segments} = target, trigger) do
    combinator = Map.get(target, :market_segments_combinator, "and")

    projects =
      case combinator do
        "and" -> Sanbase.Project.List.by_market_segment_all_of(market_segments)
        "or" -> Sanbase.Project.List.by_market_segment_any_of(market_segments)
      end

    Enum.map(projects, & &1.slug)
    |> remove_targets_on_cooldown(trigger, :slug)
  end

  defp remove_targets_on_cooldown(%{slug: slug}, trigger)
       when is_binary(slug) or is_list(slug) do
    slug
    |> List.wrap()
    |> remove_targets_on_cooldown(trigger, :slug)
  end

  defp remove_targets_on_cooldown(%{word: slug}, trigger)
       when is_binary(slug) or is_list(slug) do
    slug
    |> List.wrap()
    |> remove_targets_on_cooldown(trigger, :word)
  end

  defp remove_targets_on_cooldown(%{text: text}, trigger)
       when is_binary(text) do
    text
    |> List.wrap()
    |> remove_targets_on_cooldown(trigger, :text)
  end

  defp remove_targets_on_cooldown(%{eth_address: address}, trigger)
       when is_binary(address) or is_list(address) do
    address
    |> List.wrap()
    |> Enum.map(&Sanbase.BlockchainAddress.to_internal_format/1)
    |> remove_targets_on_cooldown(trigger, :eth_address)
  end

  defp remove_targets_on_cooldown(%{address: address}, trigger)
       when is_binary(address) or is_list(address) do
    address
    |> List.wrap()
    |> Enum.map(&Sanbase.BlockchainAddress.to_internal_format/1)
    |> remove_targets_on_cooldown(trigger, :address)
  end

  defp remove_targets_on_cooldown(target, trigger) do
    target
    |> List.wrap()
    |> remove_targets_on_cooldown(trigger, :slug)
  end

  defp remove_targets_on_cooldown(target_list, trigger, type) when is_list(target_list) do
    target_list =
      target_list
      |> Enum.reject(&Sanbase.Alert.Trigger.has_cooldown?(trigger, &1))

    %{list: target_list, type: type}
  end
end
