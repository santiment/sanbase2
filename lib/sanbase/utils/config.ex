defmodule Sanbase.Utils.Config do
  def parse_config_value({:system, env_key, default}), do: System.get_env(env_key) || default

  def parse_config_value({:system, env_key}), do: System.get_env(env_key)

  def parse_config_value(value), do: value

  defmacro get(key, default \\ nil) do
    Application.fetch_env!(:sanbase, __MODULE__)
    |> Keyword.get(key, default)
    |> parse_config_value()
  end
end
