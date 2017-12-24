defmodule Sanbase.Utils do
  def parse_config_value({:system, env_key, default}), do: System.get_env(env_key) || default
  def parse_config_value({:system, env_key}), do: System.get_env(env_key)

  def parse_config_value(value), do: value

  def removeThousandsSeparator(attrs, key) do
    attrs
    |> Map.get(key)
    |> case do
      nil -> attrs
      value ->
        Map.put(attrs, key, String.replace(value, ",", ""))
    end
  end
end
