defmodule Sanbase.Signals.StructMapTransformation do
  alias Sanbase.Signals.Trigger

  @module_type_pairs [
    {Trigger.DailyActiveAddressesSettings, "daily_active_addresses"},
    {Trigger.PricePercentChangeSettings, "price_percent_change"},
    {Trigger.PriceAbsoluteChangeSettings, "price_absolute_change"},
    {Trigger.PriceVolumeDifferenceTriggerSettings, "price_volume_difference"},
    {Trigger.TrendingWordsTriggerSettings, "trending_words"},
    {Trigger.EthWalletTriggerSettings, "eth_wallet"}
  ]

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

  def load_in_struct(map) when is_map(map) do
    map
    |> atomize_keys()
    |> struct_from_map()
  end

  def load_in_struct(_), do: :error

  # All `struct_from_map` functions are generated from the @module_type_pairs as they
  # all have the same structure and are just pattern matchin on different values
  for {module, type} <- @module_type_pairs do
    def struct_from_map(%{type: unquote(type)} = trigger_settings) do
      {:ok, struct(unquote(module), trigger_settings)}
    end
  end

  def struct_from_map(%{type: type}),
    do: {:error, "The trigger settings type '#{type}' is not a valid type."}

  def struct_from_map(_), do: {:error, "The trigger settings are missing `type` key."}

  # All `map_from_struct` functions are generated from the @module_type_pairs as they
  # all have the same structure and are just pattern matchin on different values
  for {module, _type} <- @module_type_pairs do
    def map_from_struct(%unquote(module){} = trigger_settings) do
      {:ok, Map.from_struct(trigger_settings)}
    end
  end

  def map_from_struct(%struct_name{}),
    do: {:error, "The #{inspect(struct_name)} is not a valid module defining a trigger struct."}

  def map_from_struct(_), do: {:error, "The data passed to map_from_struct/1 is not a struct"}

  # Private functions

  defp atomize_keys(map) when is_map(map) do
    for {key, val} <- map, into: %{} do
      if is_atom(key) do
        {key, atomize_keys(val)}
      else
        {atomize(key), atomize_keys(val)}
      end
    end
  end

  defp atomize_keys(data), do: data

  @compile {:inline, atomize: 1}
  defp atomize("filtered_target_list"), do: :filtered_target_list
  defp atomize(str) when is_binary(str), do: String.to_existing_atom(str)
end
