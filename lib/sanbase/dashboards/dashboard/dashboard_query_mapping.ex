defmodule Sanbase.Dashboards.DashboardQueryMapping do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Dashboards.Dashboard
  alias Sanbase.Queries.Query

  @type settings :: %{}

  @type t :: %__MODULE__{
          query_id: Query.query_id(),
          dashboard_id: Dashboard.dashboard_id(),
          settings: map(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @type dashboard_query_mapping_id :: String.t()
  @type dashboard_id :: Dashboard.dashboard_id()
  @type user_id :: non_neg_integer()

  @preload [:dashboard, :query, [dashboard: :user, query: :user]]

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "dashboard_query_mappings" do
    field(:settings, :map)

    belongs_to(:query, Query)
    belongs_to(:dashboard, Dashboard)

    timestamps()
  end

  @doc false
  def changeset(%__MODULE__{} = mapping, args) do
    mapping
    |> cast(args, [:dashboard_id, :query_id, :settings])
    |> validate_required([:dashboard_id, :query_id])
  end

  @spec by_id(dashboard_query_mapping_id, Keyword.t()) :: Ecto.Query.t()
  def by_id(id, opts \\ []) do
    from(d in __MODULE__,
      where: d.id == ^id
    )
    |> maybe_lock(opts)
    |> maybe_preload(opts)
  end

  @doc ~s"""
  Get all rows for a dashboard by its id.

  When fetcing a dashboard and its queries, the queries are not preloaded directly.
  This is because we need to populate the dashboard_query_mapping_id virutal field
  for each query by using the id of the mapping here. This cannot be done via preload,
  so instead of this we are fetching all the rows for that dashboard from the mapping table
  here, building the `queries` list and putting it in the dashboard studcture.

  NOTE: Because only the query from each row will be used, do not use the default preload
  which will also preload rthe dashboard and the dashboard user, but preload only the query parts
  """
  @spec dashboard_id_rows(dashboard_id) :: Ecto.Query.t()
  def dashboard_id_rows(dashboard_id) do
    from(d in __MODULE__,
      where: d.dashboard_id == ^dashboard_id
    )
    |> preload([:query, query: :user])
  end

  def dashboards_by_query_and_user(query_id, user_id) do
    from(m in __MODULE__,
      join: d in assoc(m, :dashboard),
      where: m.query_id == ^query_id and d.user_id == ^user_id
    )
  end

  # Private functions

  defp maybe_preload(query, opts) do
    case Keyword.get(opts, :preload?, true) do
      true ->
        preload = Keyword.get(opts, :preload, @preload)

        query |> preload(^preload)

      false ->
        query
    end
  end

  defp maybe_lock(query, opts) do
    case Keyword.get(opts, :lock_for_update, false) do
      true ->
        query |> lock("FOR UPDATE")

      false ->
        query
    end
  end
end
