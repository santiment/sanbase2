defmodule Sanbase.Signals.StructMapTransformation do
  alias Sanbase.Signals.Trigger

  alias Sanbase.Signals.Trigger.{
    DailyActiveAddressesSettings,
    PricePercentChangeSettings,
    PriceAbsoluteChangeSettings,
    PriceVolumeDifferenceTriggerSettings,
    TrendingWordsTriggerSettings
  }

  # Use __struct__ instead of %module{} to avoid circular dependencies
  def trigger_in_struct(
        %{trigger: trigger, __struct__: Sanbase.Signals.UserTrigger} = user_trigger
      ) do
    %{user_trigger | trigger: trigger_in_struct(trigger)}
  end

  def trigger_in_struct(%Trigger{settings: settings} = trigger) do
    {:ok, settings} = load_in_struct(settings)
    %{trigger | settings: settings}
  end

  def load_in_struct(trigger_settings) when is_map(trigger_settings) do
    trigger_settings =
      for {key, val} <- trigger_settings, into: %{} do
        if is_atom(key) do
          {key, val}
        else
          {String.to_existing_atom(key), val}
        end
      end

    struct_from_map(trigger_settings)
  end

  def load_in_struct(_), do: :error

  def struct_from_map(%{type: "daily_active_addresses"} = trigger_settings),
    do: {:ok, struct(DailyActiveAddressesSettings, trigger_settings)}

  def struct_from_map(%{type: "price_percent_change"} = trigger_settings),
    do: {:ok, struct(PricePercentChangeSettings, trigger_settings)}

  def struct_from_map(%{type: "price_absolute_change"} = trigger_settings),
    do: {:ok, struct(PriceAbsoluteChangeSettings, trigger_settings)}

  def struct_from_map(%{type: "trending_words"} = trigger_settings),
    do: {:ok, struct(TrendingWordsTriggerSettings, trigger_settings)}

  def struct_from_map(%{type: "price_volume_difference"} = trigger_settings),
    do: {:ok, struct(PriceVolumeDifferenceTriggerSettings, trigger_settings)}

  def struct_from_map(_), do: :error

  def map_from_struct(%DailyActiveAddressesSettings{} = trigger_settings),
    do: {:ok, Map.from_struct(trigger_settings)}

  def map_from_struct(%PricePercentChangeSettings{} = trigger_settings),
    do: {:ok, Map.from_struct(trigger_settings)}

  def map_from_struct(%PriceAbsoluteChangeSettings{} = trigger_settings),
    do: {:ok, Map.from_struct(trigger_settings)}

  def map_from_struct(%PriceVolumeDifferenceTriggerSettings{} = trigger_settings),
    do: {:ok, Map.from_struct(trigger_settings)}

  def map_from_struct(%TrendingWordsTriggerSettings{} = trigger_settings),
    do: {:ok, Map.from_struct(trigger_settings)}

  def map_from_struct(_), do: :error
end
