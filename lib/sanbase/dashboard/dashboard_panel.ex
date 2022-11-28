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
  @spec new(panel_args()) :: {:ok, t()} | {:error, any()}
  def new(args) do
    handle_panel(%__MODULE__{}, args, check_required: true)
  end

  @doc ~s"""
  Update a panel in-memory.

  This method is usually used with Dashboard.Schema.update_panel/3 so
  the changes are persisted in the database
  """
  @spec update(t(), panel_args) :: {:ok, t()} | {:error, any()}
  def update(%__MODULE__{} = panel, args) do
    handle_panel(panel, args, check_required: false)
  end

  defp handle_panel(%__MODULE__{} = panel, args, opts) do
    # Put ids if they are missing
    args =
      case get_in(args, [Access.key(:sql), Access.key(:san_query_id)]) do
        nil -> put_in(args, [Access.key(:sql), Access.key(:san_query_id)], UUID.uuid4())
        _ -> args
      end

    args =
      case get_in(args, [Access.key(:id)]) do
        nil -> put_in(args, [Access.key(:id)], UUID.uuid4())
        _ -> args
      end

    changeset = changeset(panel, args)

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
        {:error, changeset}
    end
  end

  @doc ~s"""
  Compute the SQL defined in the panel by executing it against ClickHouse.

  The SQL query and arguments are taken from the panel and are executed.
  The result is transformed by converting the Date and NaiveDateTime types to DateTime.
  """
  @spec compute(t(), non_neg_integer(), Keyword.t()) ::
          {:ok, Query.Result.t()} | {:error, String.t()}
  def compute(%__MODULE__{} = panel, querying_user_id, opts) do
    %{sql: %{"query" => query, "parameters" => parameters}} = panel
    san_query_id = get_in(panel, [Access.key(:sql), "san_query_id"])

    # If the opts contain parameters, override the default parameters during computing.
    # It allows for only some parameters to be provided. They will override the existing
    # ones and the rest will remain the same.
    parameters =
      case Keyword.get(opts, :parameters) do
        nil -> parameters
        overridden_parameters -> Map.merge(parameters, overridden_parameters)
      end

    Query.run(query, parameters, san_query_id, querying_user_id)
  end
end
