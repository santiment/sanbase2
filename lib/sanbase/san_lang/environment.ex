defmodule Sanbase.SanLang.Environment do
  @moduledoc false
  defstruct env_bindings: %{}, local_bindings: %{}

  @type t :: %__MODULE__{
          env_bindings: map(),
          local_bindings: map()
        }

  def new do
    %__MODULE__{}
  end

  def put_env_bindings(%__MODULE__{} = env, bindings) do
    Map.put(env, :env_bindings, bindings)
  end

  def add_local_binding(%__MODULE__{} = env, key, value) when is_binary(key) do
    local_bindings = Map.get(env, :local_bindings, %{})
    local_bindings = Map.put(local_bindings, key, value)
    Map.put(env, :local_bindings, local_bindings)
  end

  def clear_local_bindings(%__MODULE__{} = env), do: Map.put(env, :local_bindings, %{})

  def get_env_binding(%__MODULE__{} = env, key) when is_binary(key) do
    find_in_bindings(env, :env_bindings, key)
  end

  def get_local_binding(%__MODULE__{} = env, key) when is_binary(key) do
    find_in_bindings(env, :local_bindings, key)
  end

  # Private functions

  defp find_in_bindings(env, bindings_key, looked_up_key) do
    bindings = Map.get(env, bindings_key)

    if Map.has_key?(bindings, looked_up_key) do
      {:ok, Map.get(bindings, looked_up_key)}
    else
      keys = Map.keys(bindings)

      closest =
        if keys == [],
          do: nil,
          else: Enum.max_by(keys, &String.jaro_distance(looked_up_key, &1))

      closest_suggestion_str =
        if is_binary(closest) and String.jaro_distance(looked_up_key, closest) > 0.8,
          do: " Did you mean to use '#{closest}' as a key?",
          else: ""

      # bindings_key is either :local_bindings or :env_bindings
      bindings_str = bindings_key |> to_string() |> String.replace("_", " ")

      {:error, "Key #{inspect(looked_up_key)} not found in the #{bindings_str}.#{closest_suggestion_str}"}
    end
  end
end
