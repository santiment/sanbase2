defmodule SanbaseWeb.AdminLiveHelpers do
  @moduledoc """
  Shared helper functions used across multiple admin LiveView modules.

  Consolidates duplicated logic for:
  - Status-based record ordering (approval workflows)
  - In-memory row updates by ID
  - Changeset error flash messages
  - Integer parsing with defaults
  - Filtering metric catalog entries (see `Sanbase.Metric.Catalog`)
  - Building URL query params from filter values
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
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join(", ", fn {field, messages} ->
      "#{Phoenix.Naming.humanize(field)} #{Enum.join(messages, ", ")}"
    end)
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

  @doc """
  Filters metric maps (with `:metric` and `:human_readable_name` keys) by a
  case-insensitive query matching either field. An empty query is a no-op.
  """
  @spec filter_by_search([map()], String.t()) :: [map()]
  def filter_by_search(metrics, ""), do: metrics

  def filter_by_search(metrics, query) do
    query_lower = String.downcase(query)

    Enum.filter(metrics, fn metric ->
      String.contains?(String.downcase(metric.metric), query_lower) ||
        (metric.human_readable_name &&
           String.contains?(String.downcase(metric.human_readable_name), query_lower))
    end)
  end

  @doc """
  Filters metric maps by `:source_type` ("registry"/"code"). "all" is a no-op.
  """
  @spec filter_by_source([map()], String.t()) :: [map()]
  def filter_by_source(metrics, "all"), do: metrics
  def filter_by_source(metrics, source), do: Enum.filter(metrics, &(&1.source_type == source))

  @doc """
  Puts `key => value` into a URL query params map, skipping empty values.
  The 4-arity version also skips values equal to the given default, keeping
  URLs free of parameters that match the initial filter state.
  """
  @spec maybe_add_param(map(), String.t(), term()) :: map()
  def maybe_add_param(params, _key, ""), do: params
  def maybe_add_param(params, key, value), do: Map.put(params, key, value)

  @spec maybe_add_param(map(), String.t(), term(), term()) :: map()
  def maybe_add_param(params, _key, "", _default), do: params
  def maybe_add_param(params, _key, value, default) when value == default, do: params
  def maybe_add_param(params, key, value, _default), do: Map.put(params, key, value)
end
