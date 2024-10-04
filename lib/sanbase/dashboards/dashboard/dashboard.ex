defmodule Sanbase.Dashboards.Dashboard do
  @moduledoc ~s"""
  Dashboard database schema and CRUD functions for working
  with it.
  """

  @behaviour Sanbase.Entity.Behaviour

  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset
  import Sanbase.Utils.Transform, only: [to_bang: 1]

  alias Sanbase.Repo
  alias Sanbase.Accounts.User
  alias Sanbase.Queries.Query
  alias Sanbase.Dashboards.TextWidget
  alias Sanbase.Dashboards.ImageWidget

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          name: String.t(),
          description: String.t(),
          is_public: boolean(),
          parameters: Map.t(),
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t(),
          user: %User{}
        }

  @type create_dashboard_args :: %{
          required(:user_id) => user_id(),
          optional(:name) => String.t(),
          optional(:description) => String.t(),
          optional(:is_public) => boolean(),
          optional(:parameters) => map(),
          optional(:settings) => map()
        }

  @type update_dashboard_args :: %{
          optional(:name) => String.t(),
          optional(:description) => String.t(),
          optional(:is_public) => boolean(),
          optional(:parameters) => map(),
          optional(:settings) => map(),
          # updatable by moderators only
          optional(:is_deleted) => boolean(),
          optional(:is_hidden) => boolean()
        }

  @type option ::
          {:preload?, boolean}
          | {:preload, [atom()]}
          | {:page, non_neg_integer()}
          | {:page_size, non_neg_integer()}

  @type opts :: [option]

  @typedoc ~s"""
  The map of arguments that can be passed to the create or update functions.
  """
  @type schema_args :: %{
          optional(:name) => String.t(),
          optional(:description) => String.t(),
          optional(:is_public) => boolean(),
          optional(:user_id) => non_neg_integer()
        }

  @type dashboard_id :: non_neg_integer()
  @type user_id :: non_neg_integer()

  schema "dashboards" do
    field(:name, :string)
    field(:description, :string)
    field(:is_public, :boolean, default: false)
    field(:parameters, :map, default: %{})
    field(:settings, :map, default: %{})

    belongs_to(:user, User)

    # Linked queries
    many_to_many(
      :queries,
      Query,
      join_through: "dashboard_query_mappings",
      join_keys: [dashboard_id: :id, query_id: :id],
      on_replace: :delete,
      on_delete: :delete_all
    )

    embeds_many(:text_widgets, TextWidget, on_replace: :delete)
    embeds_many(:image_widgets, ImageWidget, on_replace: :delete)

    # Keep for backwards compatibility reasons
    embeds_many(:panels, Sanbase.Dashboard.Panel, on_replace: :delete)

    # Fields related to timeline hiding and reversible-deletion
    field(:is_hidden, :boolean, default: false)
    field(:is_deleted, :boolean, default: false)

    # Virtual fields
    field(:views, :integer, virtual: true, default: 0)
    field(:is_featured, :boolean, virtual: true)

    # Featured item related fields
    has_one(:featured_item, Sanbase.FeaturedItem,
      on_delete: :delete_all,
      foreign_key: :dashboard_id
    )

    timestamps()
  end

  @create_fields [:name, :description, :is_public, :parameters, :settings, :user_id]
  @update_fields @create_fields -- [:user_id]

  @preload [:queries, :user, :featured_item, [queries: :user]]
  def default_preload(), do: @preload

  @doc false
  def changeset(%__MODULE__{} = dashboard, attrs) do
    # Used in admin panel
    dashboard
    |> cast(attrs, @update_fields)
    |> validate_required([:name])
  end

  def create_changeset(%__MODULE__{} = dashboard, attrs) do
    dashboard
    |> cast(attrs, @create_fields)
    |> validate_required([:name, :user_id])
  end

  def update_changeset(%__MODULE__{} = dashboard, attrs) do
    dashboard
    |> cast(attrs, @update_fields)
    |> validate_required([:name])
  end

  @doc ~s"""
  Get a query in order to read or run it.
  This can be done by owner or by anyone if the query is public.
  """
  @spec get_for_read(dashboard_id, user_id | nil, opts) :: Ecto.Query.t()
  def get_for_read(dashboard_id, querying_user_id, opts \\ [])

  def get_for_read(dashboard_id, nil = _querying_user_id, opts) do
    from(
      d in base_query(),
      where: d.id == ^dashboard_id and d.is_public == true
    )
    |> maybe_preload(opts)
  end

  def get_for_read(dashboard_id, querying_user_id, opts) do
    from(
      d in base_query(),
      where: d.id == ^dashboard_id and (d.is_public == true or d.user_id == ^querying_user_id)
    )
    |> maybe_preload(opts)
  end

  @doc ~s"""
  Get a query in order to mutate it (update or delete).
  Only the owner of the query can do that.
  """
  @spec get_for_mutation(dashboard_id, user_id, opts) :: Ecto.Query.t()
  def get_for_mutation(dashboard_id, querying_user_id, opts) when not is_nil(querying_user_id) do
    from(
      d in base_query(),
      where: d.id == ^dashboard_id and d.user_id == ^querying_user_id,
      lock: "FOR UPDATE"
    )
    |> maybe_preload(opts)
  end

  @doc ~s"""
  Get a query in order to update its cache.
  Only the owner of the query can do that when the dashboard is private.
  Public dashboard's cache can be refreshed by anyone.
  """
  @spec get_for_cache_update(dashboard_id, user_id, opts) :: Ecto.Query.t()
  def get_for_cache_update(dashboard_id, querying_user_id, opts)
      when not is_nil(querying_user_id) do
    from(
      d in base_query(),
      where: d.id == ^dashboard_id and (d.user_id == ^querying_user_id or d.is_public == true),
      lock: "FOR UPDATE"
    )
    |> maybe_preload(opts)
  end

  @spec get_user_dashboards(dashboard_id, user_id | nil, opts) :: Ecto.Query.t()
  def get_user_dashboards(user_id, querying_user_id, opts) do
    where =
      case querying_user_id do
        nil ->
          # only the public dashboards if no user
          dynamic([d], d.user_id == ^user_id and d.is_public == true)

        _ ->
          # all dashboards if querying_user_id == user_id, the public ones otherwise
          dynamic(
            [d],
            d.user_id == ^user_id and (d.is_public == true or d.user_id == ^querying_user_id)
          )
      end

    from(
      d in base_query(),
      where: ^where,
      preload: ^@preload
    )
    |> paginate(opts)
    |> maybe_preload(opts)
  end

  # Entity Behaviour functions

  @impl Sanbase.Entity.Behaviour
  def get_visibility_data(id) do
    Sanbase.Entity.Query.default_get_visibility_data(__MODULE__, :dashboard, id)
  end

  @impl Sanbase.Entity.Behaviour
  @spec by_id(non_neg_integer(), opts) :: {:ok, t()} | {:error, String.t()}
  def by_id(dashboard_id, opts \\ []) do
    query = from(d in __MODULE__, where: d.id == ^dashboard_id)

    # The frontend can emit multiple updateDashboardPanel requests in parallel
    # and they can end up executing on multiple backend nodes. In such case,
    # without locking, a race condition is possible and not all updates
    # will be applied.
    query =
      case Keyword.get(opts, :lock_for_update, false) do
        false -> query
        true -> query |> lock("FOR UPDATE")
      end

    case Repo.one(query) do
      %__MODULE__{} = dashboard -> {:ok, dashboard}
      nil -> {:error, "Dashboard does not exist"}
    end
  end

  @impl Sanbase.Entity.Behaviour
  def by_id!(dashboard_id, opts \\ []),
    do: by_id(dashboard_id, opts) |> to_bang()

  @impl Sanbase.Entity.Behaviour
  def by_ids(ids, opts) when is_list(ids) do
    preload = Keyword.get(opts, :preload, [:featured_item])

    result =
      from(ul in base_query(),
        where: ul.id in ^ids,
        preload: ^preload,
        order_by: fragment("array_position(?, ?::int)", ^ids, ul.id)
      )
      |> Repo.all()

    {:ok, result}
  end

  @impl Sanbase.Entity.Behaviour
  def by_ids!(ids, opts \\ []), do: by_ids(ids, opts) |> to_bang()

  @impl Sanbase.Entity.Behaviour
  def public_and_user_entity_ids_query(user_id, opts) do
    base_entity_ids_query(opts)
    |> where([d], d.is_public == true or d.user_id == ^user_id)
  end

  @impl Sanbase.Entity.Behaviour
  def public_entity_ids_query(opts) do
    base_entity_ids_query(opts)
    |> where([d], d.is_public == true)
  end

  @impl Sanbase.Entity.Behaviour
  def user_entity_ids_query(user_id, opts) do
    # Disable the filter by users
    opts = Keyword.put(opts, :user_ids, nil)

    base_entity_ids_query(opts)
    |> where([ul], ul.user_id == ^user_id)
  end

  def public?(dashboard), do: dashboard.is_public

  # Private functions

  defp base_query() do
    from(conf in __MODULE__, where: conf.is_deleted != true)
  end

  # The base of all the entity queries
  defp base_entity_ids_query(opts) do
    base_query()
    |> Sanbase.Entity.Query.maybe_filter_is_hidden(opts)
    |> Sanbase.Entity.Query.maybe_filter_is_featured_query(opts, :dashboard_id)
    |> Sanbase.Entity.Query.maybe_filter_by_users(opts)
    |> Sanbase.Entity.Query.maybe_filter_by_cursor(:inserted_at, opts)
    |> Sanbase.Entity.Query.maybe_filter_min_title_length(opts, :name)
    |> Sanbase.Entity.Query.maybe_filter_min_description_length(
      opts,
      :description
    )
    |> select([ul], ul.id)
  end

  defp paginate(query, opts) do
    {limit, offset} = Sanbase.Utils.Transform.opts_to_limit_offset(opts)

    query
    |> limit(^limit)
    |> offset(^offset)
  end

  defp maybe_preload(query, opts) do
    case Keyword.get(opts, :preload?, true) do
      false ->
        query

      true ->
        preload = opts |> Keyword.get(:preload, @preload)
        query |> preload(^preload)
    end
  end
end
