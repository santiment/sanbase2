defmodule Sanbase.EnvConfigLoader do
  @moduledoc """
  Loads `.env` and `.env.<mix_env>` files into system environment variables.
  """

  require Logger

  @doc """
  Loads `.env` and the Mix.env-specific env file (e.g. `.env.test`).
  """
  @spec auto_load() :: :ok
  def auto_load do
    current_env = Mix.env() |> Atom.to_string()
    load([".env", ".env.#{current_env}"])
  end

  @doc """
  Loads a list of env files, setting their key=value pairs as system env vars.
  """
  @spec load([String.t()]) :: :ok
  def load(env_files) do
    Enum.each(env_files, fn path ->
      with {:ok, content} <- File.read(path) do
        count = parse_and_load(content)
        Logger.debug("Loaded #{count} env vars from #{path}")
      else
        {:error, :enoent} -> :ok
        {:error, reason} -> Logger.warning("Failed loading #{path}: #{inspect(reason)}")
      end
    end)
  end

  defp parse_and_load(content) do
    content
    |> String.split("\n")
    |> Enum.reject(&(&1 == "" or Regex.match?(~r/^\s*#/, &1)))
    |> Enum.count(&load_line/1)
  end

  defp load_line(line) do
    case String.split(String.trim(line), "=", parts: 2) do
      [key, value] ->
        System.put_env(String.upcase(key), parse_value(value))
        true

      _ ->
        false
    end
  end

  defp parse_value("\"" <> _ = value) do
    value
    |> String.split(~r{(?<!\\)"}, parts: 3)
    |> Enum.at(1, "")
    |> String.replace(~r{\\"}, ~S("))
  end

  defp parse_value(value) do
    value |> String.split("#", parts: 2) |> hd()
  end
end
