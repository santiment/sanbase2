defmodule Sanbase.Utils.Config do
  def parse_config_value({:system, env_key, default}) do
    System.get_env(env_key) || default
  end

  def parse_config_value({:system, env_key}) do
    System.get_env(env_key)
  end

  def parse_config_value(value) do
    value
  end

  defmacro compile_get(key) do
    quote bind_quoted: [key: key] do
      Application.compile_env!(:sanbase, __MODULE__)
      |> Keyword.get(key)
      |> Sanbase.Utils.Config.parse_config_value()
    end
  end

  defmacro get(key) do
    quote bind_quoted: [key: key] do
      Application.fetch_env!(:sanbase, __MODULE__)
      |> Keyword.get(key)
      |> Sanbase.Utils.Config.parse_config_value()
    end
  end

  defmacro get(key, default) do
    quote bind_quoted: [key: key, default: default] do
      Application.fetch_env(:sanbase, __MODULE__)
      |> case do
        {:ok, env} -> env |> Keyword.get(key, default)
        _ -> default
      end
      |> Sanbase.Utils.Config.parse_config_value()
    end
  end

  defmacro module_get(module, key) do
    quote bind_quoted: [module: module, key: key] do
      Application.fetch_env!(:sanbase, module)
      |> Keyword.get(key)
      |> Sanbase.Utils.Config.parse_config_value()
    end
  end

  defmacro module_get!(module, key) do
    quote bind_quoted: [module: module, key: key] do
      Application.fetch_env!(:sanbase, module)
      |> Keyword.fetch!(key)
      |> Sanbase.Utils.Config.parse_config_value()
    end
  end

  def parse_boolean_value(value) do
    cond do
      value in [0, false] or (is_binary(value) and String.downcase(value) in ["false", "0"]) ->
        false

      value in [1, true] or (is_binary(value) and String.downcase(value) in ["true", "1"]) ->
        true

      true ->
        nil
    end
  end

  defmacro module_get(module, key, default) do
    quote bind_quoted: [module: module, key: key, default: default] do
      Application.fetch_env(:sanbase, module)
      |> case do
        {:ok, env} -> env |> Keyword.get(key, default)
        _ -> default
      end
      |> Sanbase.Utils.Config.parse_config_value()
    end
  end

  def module_get_integer!(module, key) do
    module_get!(module, key) |> Sanbase.Math.to_integer()
  end

  def mogule_get_boolean(module, key, default) do
    case module_get_boolean(module, key) do
      nil -> default
      bool when is_boolean(bool) -> bool
    end
  end

  def module_get_boolean(module, key) do
    module_get(module, key)
    |> parse_boolean_value()
  end
end
