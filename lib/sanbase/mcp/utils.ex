defmodule Sanbase.MCP.Utils do
  @moduledoc """
  Common utility functions for MCP tools.
  """

  @doc """
  Parses a time period string and returns a {from_datetime, to_datetime} tuple.

  ## Examples

      iex> Sanbase.MCP.Utils.parse_time_period("1h", ~U[2025-09-10 00:00:00Z])
      {:ok, {~U[2025-09-09 23:00:00Z], ~U[2025-09-10 00:00:00Z]}}

      iex> Sanbase.MCP.Utils.parse_time_period("invalid")
      {:error, "Invalid time period format. Use format like '1h', '6h', '1d', '7d'"}
  """
  @spec parse_time_period(String.t(), DateTime.t()) ::
          {:ok, {DateTime.t(), DateTime.t()}} | {:error, String.t()}
  def parse_time_period(time_period, now \\ DateTime.utc_now()) do
    # The now parameter allows for deterministic testing by providing a fixed reference time instead of using the current system time.
    if Sanbase.DateTimeUtils.valid_interval?(time_period) do
      seconds = Sanbase.DateTimeUtils.str_to_sec(time_period)
      to_datetime = now
      from_datetime = DateTime.add(to_datetime, -seconds, :second)
      {:ok, {from_datetime, to_datetime}}
    else
      {:error, "Invalid time period format. Use format like '1h', '6h', '1d', '7d'"}
    end
  end

  @doc """
  Validates a size parameter, ensuring it's between 1 and 30.

  ## Examples

      iex> Sanbase.MCP.Utils.validate_size(10, 1, 10)
      {:ok, 10}

      iex> Sanbase.MCP.Utils.validate_size(50, 1, 10)
      {:error, "Size must be between 1 and 10 inclusively, got: 50"}

      iex> Sanbase.MCP.Utils.validate_size("invalid", 1, 10)
      {:error, "Size must be an integer"}
  """
  @spec validate_size(non_neg_integer(), non_neg_integer(), non_neg_integer()) ::
          {:ok, pos_integer()} | {:error, String.t()}
  def validate_size(size, min, max) when is_integer(size) and size >= min and size <= max do
    {:ok, size}
  end

  def validate_size(size, min, max) when is_integer(size) do
    {:error, "Size must be between #{min} and #{max} inclusively, got: #{size}"}
  end

  def validate_size(_size, _min, _max) do
    {:error, "Size must be an integer"}
  end
end
