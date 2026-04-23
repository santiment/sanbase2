defmodule SanbaseWeb.AdminLiveHelpers do
  @moduledoc """
  Shared helper functions used across multiple admin LiveView modules.

  Consolidates duplicated logic for:
  - Status-based record ordering (approval workflows)
  - In-memory row updates by ID
  - Changeset error flash messages
  - Integer parsing with defaults
  """

  import Phoenix.LiveView, only: [put_flash: 3]

  @status_order %{"pending_approval" => 1, "approved" => 2, "declined" => 3}

  @doc """
  Sorts records by status (pending first, then approved, then declined),
  with a secondary sort by id descending within each status group.
  """
  def order_records_by_status(records) do
    Enum.sort_by(records, fn record ->
      {Map.get(@status_order, record.status, 99), -record.id}
    end)
  end

  @doc """
  Updates a single record in a list by its ID, applying the given updates map.
  Returns the updated list re-ordered by status.

  ## Examples

      update_row_by_id(rows, 42, %{status: "approved"})
  """
  def update_row_by_id(rows, record_id, updates) when is_map(updates) do
    rows
    |> Enum.map(fn
      %{id: id} = record when id == record_id ->
        Enum.reduce(updates, record, fn {key, value}, acc ->
          Map.put(acc, key, value)
        end)

      record ->
        record
    end)
    |> order_records_by_status()
  end

  @doc """
  Adds an error flash message from a changeset or error string.
  """
  def put_changeset_error_flash(socket, changeset_or_error, prefix \\ "Error") do
    error_msg =
      case changeset_or_error do
        %Ecto.Changeset{} = changeset ->
          Sanbase.Utils.ErrorHandling.changeset_errors_string(changeset)

        error when is_binary(error) ->
          error
      end

    put_flash(socket, :error, "#{prefix}.\n Reason: #{error_msg}!")
  end

  @doc """
  Formats an Ecto.Changeset's errors as a comma-separated string.

  ## Example

      "Name can't be blank, Display order must be an integer"
  """
  def format_errors(%Ecto.Changeset{} = changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _}} ->
      "#{Phoenix.Naming.humanize(field)} #{message}"
    end)
    |> Enum.join(", ")
  end

  @doc """
  Parses a string to integer with a default fallback.
  """
  def parse_int(nil, default), do: default
  def parse_int(value, _default) when is_integer(value), do: value

  def parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end
end
