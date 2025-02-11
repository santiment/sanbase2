defmodule Sanbase.Utils.Config do
  @moduledoc ~s"""
  Module for reading configuration values from the application environment.
  """

  def module_get(module, key_or_keys)
      when is_atom(key_or_keys) or is_list(key_or_keys) do
    keys = List.wrap(key_or_keys)

    Application.fetch_env!(:sanbase, module)
    |> get_in(keys)
    |> parse_config_value()
  end

  def module_get!(module, key) do
    Application.fetch_env!(:sanbase, module)
    |> Keyword.fetch!(key)
    |> parse_config_value()
  end

  def module_get(module, key_or_keys, default)
      when is_atom(key_or_keys) or is_list(key_or_keys) do
    keys = List.wrap(key_or_keys)

    case Application.fetch_env(:sanbase, module) do
      {:ok, env} -> get_in(env, keys)
      _ -> default
    end
    |> parse_config_value()
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

  def parse_config_value({:system, env_key, default}) do
    System.get_env(env_key) || default
  end

  def parse_config_value({:system, env_key}) do
    System.get_env(env_key)
  end

  def parse_config_value(value) do
    value
  end
end
