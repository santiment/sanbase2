defmodule Sanbase.Utils do
  def parse_config_value({:system, env_key, default}), do: System.get_env(env_key) || default
  def parse_config_value({:system, env_key}), do: System.get_env(env_key)

  def parse_config_value(value), do: value
end
