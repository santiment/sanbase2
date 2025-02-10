defmodule Sanbase.Dashboard.Panel do
  @moduledoc ~s"""
  A dashboard panel is a component of a dashboard that encapsulates a
  Clickhouse query and how it's visualized on the dashboard.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Dashboard.Query

  @type sql :: %{
          query: String.t(),
          parameters: list(String.t() | DateTime.t() | List.t() | number() | boolean())
        }

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          description: String.t(),
          settings: map(),
          sql: sql()
        }

  @type panel_args :: %{
          optional(:name) => String.t(),
          optional(:description) => String.t(),
          optional(:settings) => Map.t(),
          optional(:sql) => sql()
        }

  embedded_schema do
    # Auotegenerate on creation
    field(:name, :string)
    field(:description, :string)
    field(:settings, :map)
    field(:sql, :map)
  end

  def changeset(%__MODULE__{} = panel, attrs) do
    panel
    |> cast(attrs, [:name, :description, :settings, :sql])
    |> validate_change(:sql, &Query.changeset_valid_sql?/2)
  end

  @doc ~s"""
  Create a struct from the provided arguments

  The struct exists only in memory and should manually be put
  inside a dashboard
  """
  @spec new(panel_args(), Keyword.t()) :: {:ok, t()} | {:ok, Ecto.Changeset.t()} | {:error, any()}
  def new(args, opts \\ []) do
    opts = Keyword.merge([check_required: true, put_id: true, as_changeset: false], opts)
    handle_panel(%__MODULE__{}, args, opts)
  end

  @doc ~s"""
  Update a panel in-memory.

  This method is usually used with Dashboard.Schema.update_panel/3 so
  the changes are persisted in the database
  """
  @spec update(t(), panel_args, Keyword.t()) ::
          {:ok, t()} | {:ok, Ecto.Changeset.t()} | {:error, any()}
  def update(%__MODULE__{} = panel, args, opts \\ []) do
    opts = Keyword.merge([check_required: false, put_id: false, as_changeset: true], opts)
    handle_panel(panel, args, opts)
  end

  defp handle_panel(%__MODULE__{} = panel, args, opts) do
    args =
      if Keyword.get(opts, :put_id) do
        put_in(args, [:id], UUID.uuid4())
      else
        args
      end

    args = args |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> Map.new()

    changeset = changeset(panel, args)

    changeset =
      if Keyword.fetch!(opts, :check_required) do
        validate_required(changeset, [:sql])
      else
        changeset
      end

    if changeset.valid? do
      # In case of panel update, in order for `put_embed` to be able to detect
      # that an existing panel is being updated, it needs to be added as a changeset
      if Keyword.get(opts, :as_changeset, false) do
        {:ok, changeset}
      else
        {:ok, Map.merge(panel, args)}
      end
    else
      {:error, changeset}
    end
  end

  @doc ~s"""
  Compute the SQL defined in the panel by executing it against ClickHouse.

  The SQL query and arguments are taken from the panel and are executed.
  The result is transformed by converting the Date and NaiveDateTime types to DateTime.
  """
  @spec compute(t(), Dashboard.Schema.t(), map()) ::
          {:ok, Query.Result.t()} | {:error, String.t()}
  def compute(%__MODULE__{} = panel, dashboard, query_metadata) do
    %{sql: %{"query" => query, "parameters" => parameters}} = panel
    parameters = Map.merge(parameters, dashboard.parameters)

    Query.run(query, parameters, query_metadata)
  end
end
