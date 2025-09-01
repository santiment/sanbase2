defmodule Sanbase.MCP.Utils do
  @moduledoc """
  Common utility functions for MCP tools.
  """

  @doc """
  Parses a time period string and returns a {from_datetime, to_datetime} tuple.

  ## Examples

      iex> Sanbase.MCP.Utils.parse_time_period("1h")
      {:ok, {from_datetime, to_datetime}}

      iex> Sanbase.MCP.Utils.parse_time_period("invalid")
      {:error, "Invalid time period format. Use format like '1h', '6h', '1d', '7d'"}
  """
  @spec parse_time_period(String.t()) ::
          {:ok, {DateTime.t(), DateTime.t()}} | {:error, String.t()}
  def parse_time_period(time_period) do
    if Sanbase.DateTimeUtils.valid_interval?(time_period) do
      seconds = Sanbase.DateTimeUtils.str_to_sec(time_period)
      to_datetime = DateTime.utc_now()
      from_datetime = DateTime.add(to_datetime, -seconds, :second)
      {:ok, {from_datetime, to_datetime}}
    else
      {:error, "Invalid time period format. Use format like '1h', '6h', '1d', '7d'"}
    end
  end

  @doc """
  Validates a size parameter, ensuring it's between 1 and 30.

  ## Examples

      iex> Sanbase.MCP.Utils.validate_size(10)
      {:ok, 10}

      iex> Sanbase.MCP.Utils.validate_size(50)
      {:error, "Size must be between 1 and 30, got: 50"}

      iex> Sanbase.MCP.Utils.validate_size("invalid")
      {:error, "Size must be an integer"}
  """
  @spec validate_size(any()) :: {:ok, pos_integer()} | {:error, String.t()}
  def validate_size(size) when is_integer(size) and size > 0 and size <= 30 do
    {:ok, size}
  end

  def validate_size(size) when is_integer(size) do
    {:error, "Size must be between 1 and 30, got: #{size}"}
  end

  def validate_size(_) do
    {:error, "Size must be an integer"}
  end
end
