defmodule Sanbase.Utils.Config do
  alias __MODULE__, as: Config

  def parse_config_value({:system, env_key, default}) do
    System.get_env(env_key) || default
  end

  def parse_config_value({:system, env_key}) do
    System.get_env(env_key)
  end

  def parse_config_value(value) do
    value
  end

  defmacro get(key) do
    quote bind_quoted: [key: key] do
      Application.fetch_env!(:sanbase, __MODULE__)
      |> Keyword.get(key)
      |> Config.parse_config_value()
    end
  end

  defmacro get(key, default) do
    quote bind_quoted: [key: key, default: default] do
      Application.fetch_env!(:sanbase, __MODULE__)
      |> Keyword.get(key, default)
      |> Config.parse_config_value()
    end
  end

  defmacro module_get(module, key) do
    quote bind_quoted: [module: module, key: key] do
      Application.fetch_env!(:sanbase, module)
      |> Keyword.get(key)
      |> Config.parse_config_value()
    end
  end

  defmacro module_get(module, key, default) do
    quote bind_quoted: [module: module, key: key, default: default] do
      Application.fetch_env!(:sanbase, module)
      |> Keyword.get(key, default)
      |> Config.parse_config_value()
    end
  end
end
