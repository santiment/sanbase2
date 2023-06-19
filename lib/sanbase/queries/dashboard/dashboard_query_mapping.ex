defmodule Sanbase.Queries.DashboardQueryMapping do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Queries.Dashboard
  alias Sanbase.Queries.Query

  @type settings :: %{}

  @type t :: %__MODULE__{
          query_id: Query.query_id(),
          dashboard_id: Dashboard.dashboard_id(),
          settings: map(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @type dashboard_id :: Dashboard.dashboard_id()
  @type dashboard_query_mapping_id :: non_neg_integer()
  @type user_id :: non_neg_integer()

  @preload [:dashboard, :query]

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
    |> maybe_preload(opts)
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
end
