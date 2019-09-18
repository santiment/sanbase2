defmodule Sanbase.Signal.StructMapTransformation do
  alias Sanbase.Signal.Trigger

  @unsupported_fields_error :__internal_unsupported_field_errors__

  @signal_modules Sanbase.Signal.List.get()

  @module_type_pairs for module <- @signal_modules, do: {module, module.type}

  # Use __struct__ instead of %module{} to avoid circular dependencies
  def trigger_in_struct(
        %{trigger: trigger, __struct__: Sanbase.Signal.UserTrigger} = user_trigger
      ) do
    %{user_trigger | trigger: trigger_in_struct(trigger)}
  end

  def trigger_in_struct(%Trigger{settings: settings} = trigger) do
    {:ok, settings} = load_in_struct(settings)
    %{trigger | settings: settings}
  end

  def load_in_struct_if_valid(map) when is_map(map) do
    atomized_map =
      map
      |> atomize_keys()

    unsupported_fields_error = Process.get(@unsupported_fields_error)
    Process.delete(@unsupported_fields_error)

    case unsupported_fields_error do
      nil ->
        struct_from_map(atomized_map)

      errors ->
        {:error, errors |> Enum.join(",")}
    end
  end

  def load_in_struct(map) when is_map(map) do
    result =
      map
      |> atomize_keys()
      |> struct_from_map()

    Process.delete(@unsupported_fields_error)

    result
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

  defp atomize_keys(list) when is_list(list) do
    Enum.map(list, fn elem -> atomize_keys(elem) end)
  end

  defp atomize_keys(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {key, val}, acc ->
      try do
        Map.put(acc, atomize(key), atomize_keys(val))
      rescue
        ArgumentError ->
          [{:erlang, :binary_to_existing_atom, [str, _], _} | _] = __STACKTRACE__

          errors = Process.get(@unsupported_fields_error, [])

          Process.put(@unsupported_fields_error, [
            ~s/The trigger contains unsupported or mistyped field "#{str}"/ | errors
          ])

          acc
      end
    end)
  end

  defp atomize_keys(data), do: data

  @compile {:inline, atomize: 1}
  defp atomize(atom) when is_atom(atom), do: atom
  defp atomize("filtered_target_list"), do: :filtered_target_list
  defp atomize(str) when is_binary(str), do: String.to_existing_atom(str)
end
