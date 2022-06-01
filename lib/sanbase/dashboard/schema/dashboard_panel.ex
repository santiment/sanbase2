defmodule Sanbase.Dashboard.Panel do
  @moduledoc ~s"""
  A dashboard panel is a component of a dashboard that encapsulates a
  Clickhouse query and how it's visualized on the dashboard.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Dashboard.Query

  @type sql :: %{
          san_query_id: String.t(),
          query: String.t(),
          args: list(String.t() | DateTime.t() | List.t() | number() | boolean())
        }

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          description: String.t(),
          type: String.t(),
          position: map(),
          size: map(),
          sql: sql()
        }

  @type panel_args :: %{
          optional(:name) => String.t(),
          optional(:description) => String.t(),
          optional(:position) => String.t(),
          optional(:size) => Map.t(),
          optional(:sql) => sql()
        }

  embedded_schema do
    # Auotegenerate on creation
    field(:name, :string)
    field(:description, :string)
    field(:position, :map)
    field(:size, :map)
    field(:type, :string)
    field(:sql, :map)
  end

  @doc ~s"""
  Create a struct from the provided arguments

  The struct exists only in memory and should manually be put
  inside a dashboard
  """
  @spec new(panel_args()) :: {:ok, t()} | {:error, any()}
  def new(args) do
    handle_panel(%__MODULE__{}, args, check_required: true, put_san_query_id: true)
  end

  @doc ~s"""
  Update a panel in-memory.

  This method is usually used with Dashboard.Schema.update_panel/3 so
  the changes are persisted in the database
  """
  @spec update(t(), panel_args) :: {:ok, t()} | {:error, any()}
  def update(%__MODULE__{} = panel, args) do
    handle_panel(panel, args, check_required: false, put_san_query_id: false)
  end

  defp handle_panel(%__MODULE__{} = panel, args, opts) do
    args =
      case Keyword.get(opts, :put_san_query_id) do
        true -> put_in(args, [:sql, :san_query_id], UUID.uuid4())
        false -> args
      end

    changeset =
      panel
      |> cast(args, [
        :name,
        :description,
        :position,
        :type,
        :size,
        :sql
      ])
      |> validate_change(:sql, &valid_sql?/2)

    changeset =
      case Keyword.fetch!(opts, :check_required) do
        true -> changeset |> validate_required([:sql])
        false -> changeset
      end

    case changeset.valid? do
      true ->
        struct = Map.merge(panel, args)
        {:ok, struct}

      false ->
        {:error, changeset.errors}
    end
  end

  @doc ~s"""
  Compute the SQL defined in the panel by executing it against ClickHouse.

  The SQL query and arguments are taken from the panel and are executed.
  The result is transformed by converting the Date and NaiveDateTime types to DateTime.
  """
  def compute(%__MODULE__{} = panel) do
    %{sql: %{"query" => query, "args" => args, "query_id" => query_id}} = panel

    query_start_time = DateTime.utc_now()

    case Sanbase.ClickhouseRepo.query_transform_with_metadata(
           query,
           args,
           &transform_result/1
         ) do
      {:ok, map} ->
        {:ok,
         %Query.Result{
           san_query_id: query_id,
           clickhouse_query_id: map.query_id,
           summary_json: Jason.encode!(map.summary),
           rows: map.rows,
           compressed_rows_json: :zlib.gzip(Jason.encode!(map.rows)),
           columns: map.columns,
           query_start_time: query_start_time,
           query_end_time: DateTime.utc_now()
         }}

      {:error, error} ->
        # This error is nice enough to be logged and returned to the user.
        # The stacktrace is parsed and relevant error messages like
        # `table X does not exist` are extracted
        {:error, error}
    end
  end

  # Private functions

  # This is passed as the transform function to the ClickhouseRepo function
  # It is executed for every row in the result set
  defp transform_result(list), do: Enum.map(list, &handle_result_param/1)

  defp handle_result_param(%Date{} = date),
    do: DateTime.new!(date, ~T[00:00:00])

  defp handle_result_param(%NaiveDateTime{} = ndt),
    do: DateTime.from_naive!(ndt, "Etc/UTC")

  defp handle_result_param(data), do: data

  defp valid_sql?(_changeset, sql) do
    with :ok <- valid_sql_query?(sql),
         :ok <- valid_sql_args?(sql) do
      []
    else
      error -> [sql: error]
    end
  end

  defp valid_sql_query?(sql) do
    case Map.has_key?(sql, :query) and is_binary(sql[:query]) do
      true -> Sanbase.Dashboard.SqlValidation.validate(sql[:query])
      false -> {:error, "sql query must be a binary string"}
    end
  end

  defp valid_sql_args?(sql) do
    case Map.has_key?(sql, :args) and is_list(sql[:args]) do
      true -> :ok
      false -> {:error, "sql args must be a list"}
    end
  end
end
