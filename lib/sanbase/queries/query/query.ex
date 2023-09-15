defmodule Sanbase.Queries.Query do
  @moduledoc ~s"""
  TODO
  """

  @behaviour Sanbase.Entity.Behaviour

  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset
  import Sanbase.Utils.Transform, only: [to_bang: 1]

  alias Sanbase.Accounts.User

  @type query_id :: non_neg_integer()
  @type user_id :: non_neg_integer()

  @type create_query_args :: %{
          required(:user_id) => user_id(),
          required(:uuid) => String.t(),
          optional(:name) => String.t(),
          optional(:description) => String.t(),
          optional(:is_public) => boolean(),
          optional(:settings) => map(),
          optional(:sql_query_text) => String.t(),
          optional(:sql_query_parameters) => Map.t(),
          optional(:origin_id) => non_neg_integer()
        }

  @type update_query_args :: %{
          optional(:name) => String.t(),
          optional(:description) => String.t(),
          optional(:is_public) => boolean(),
          optional(:settings) => map(),
          optional(:sql_query_text) => String.t(),
          optional(:sql_query_parameters) => Map.t(),
          optional(:origin_id) => non_neg_integer(),
          # updatable by moderators only
          optional(:is_deleted) => boolean(),
          optional(:is_hidden) => boolean()
        }

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          uuid: String.t(),
          origin_id: non_neg_integer(),
          name: String.t(),
          description: String.t(),
          is_public: boolean(),
          settings: map(),
          sql_query_text: String.t(),
          sql_query_parameters: map(),
          user_id: non_neg_integer(),
          is_deleted: boolean(),
          is_hidden: boolean(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @preload [:user]

  @timestamps_opts [type: :utc_datetime]
  schema "queries" do
    field(:uuid, :string)
    # If the query is a duplicate of another query, origin_id points to that original query
    # This is used to track changes.
    field(:origin_id, :integer)

    field(:name, :string)
    field(:description, :string)
    field(:is_public, :boolean, default: true)
    field(:settings, :map)

    # SQL-related fields
    field(:sql_query_text, :string, default: "")
    field(:sql_query_parameters, :map, default: %{})

    belongs_to(:user, User)

    # Fields related to timeline hiding and reversible-deletion
    field(:is_deleted, :boolean)
    field(:is_hidden, :boolean)

    timestamps()
  end

  @create_fields ~w(name description is_public settings sql_query_text sql_query_parameters user_id origin_id uuid)a
  @required_fields ~w(user_id uuid)a
  @doc false
  def create_changeset(%__MODULE__{} = query, attrs) do
    query
    |> cast(attrs, @create_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1, max: 512)
    |> validate_length(:description, min: 1, max: 5_000)
    |> validate_length(:sql_query_text, min: 1, max: 20_000)
  end

  @update_fields @create_fields -- [:user_id, :uuid]
  @doc false
  def update_changeset(%__MODULE__{} = query, attrs) do
    query
    |> cast(attrs, @update_fields)
    |> validate_length(:description, min: 1, max: 5_000)
    |> validate_length(:name, min: 1, max: 512)
    |> validate_length(:sql_query_text, min: 1, max: 20_000)
  end

  @doc ~s"""
  Create an ephemeral struct with the given SQL parameters.
  This is used as a wrapper around the SQL query and its parameters
  when running an arbitrary SQL that is not stored in the database.
  """
  def ephemeral_struct(sql_query_text, sql_query_parameters) do
    %__MODULE__{
      sql_query_text: sql_query_text,
      sql_query_parameters: sql_query_parameters
    }
  end

  @doc ~s"""
  Get a query in order to read or run it.
  This can be done by owner or by anyone if the query is public.
  """
  @spec get_for_read(query_id, user_id | nil, Keyword.t()) :: Ecto.Query.t()
  def get_for_read(query_id, querying_user_id, opts \\ [])

  def get_for_read(query_id, nil, opts) do
    from(
      q in base_query(),
      where: q.id == ^query_id and q.is_public == true
    )
    |> maybe_preload(opts)
  end

  def get_for_read(query_id, querying_user_id, opts) do
    from(
      q in base_query(),
      where: q.id == ^query_id and (q.is_public == true or q.user_id == ^querying_user_id)
    )
    |> maybe_preload(opts)
  end

  @doc ~s"""
  Get a query in order to mutate it (update or delete).
  Only the owner of the query can do that.
  """
  @spec get_for_mutation(query_id, user_id, Keyword.t()) :: Ecto.Query.t()
  def get_for_mutation(query_id, querying_user_id, opts \\ [])

  def get_for_mutation(query_id, querying_user_id, opts) when not is_nil(querying_user_id) do
    from(
      q in base_query(),
      where: q.id == ^query_id and q.user_id == ^querying_user_id
    )
    |> maybe_preload(opts)
  end

  @doc ~s"""
  Get all queries of a given user for reading.
  Users can see all of their own queries. Other users can see only the public queries.
  """
  @spec get_user_queries(user_id, user_id, Keyword.t()) :: Ecto.Query.t()
  @spec get_user_queries(user_id, nil, Keyword.t()) :: Ecto.Query.t()
  def get_user_queries(user_id, querying_user_id, opts \\ [])

  def get_user_queries(user_id, nil = _querying_user_id, opts) do
    from(
      q in base_query(),
      where: q.user_id == ^user_id and q.is_public == true,
      order_by: [desc: q.updated_at]
    )
    |> paginate(opts)
    |> maybe_preload(opts)
  end

  def get_user_queries(user_id, querying_user_id, opts) do
    from(
      q in base_query(),
      where: q.user_id == ^user_id and (q.is_public == true or q.user_id == ^querying_user_id),
      order_by: [desc: q.updated_at]
    )
    |> paginate(opts)
    |> maybe_preload(opts)
  end

  @spec get_public_queries(Keyword.t()) :: Ecto.Query.t()
  def get_public_queries(opts) do
    from(
      q in base_query(),
      where: q.is_public == true
    )
    |> paginate(opts)
    |> maybe_preload(opts)
  end

  # Entity-based queries

  @impl Sanbase.Entity.Behaviour
  def by_id!(id, opts) when is_integer(id), do: by_id(id, opts) |> to_bang()

  @impl Sanbase.Entity.Behaviour
  def by_id(id, _opts) when is_integer(id) do
    query = from(ut in base_query(), where: ut.id == ^id)

    case Repo.one(query) do
      %__MODULE__{} = struct -> {:ok, struct}
      nil -> {:error, "Query with id #{id} does not exist"}
    end
  end

  @impl Sanbase.Entity.Behaviour
  def by_ids!(ids, opts) when is_list(ids), do: by_ids(ids, opts) |> to_bang()

  @impl Sanbase.Entity.Behaviour
  def by_ids(ids, opts) when is_list(ids) do
    result =
      from(ul in base_query(),
        where: ul.id in ^ids,
        order_by: fragment("array_position(?, ?::int)", ^ids, ul.id)
      )
      |> maybe_preload(opts)
      |> Repo.all()

    {:ok, result}
  end

  # The base of all the entity queries
  defp base_entity_ids_query(opts) do
    base_query()
    |> Sanbase.Entity.Query.maybe_filter_is_hidden(opts)
    # |> Sanbase.Entity.Query.maybe_filter_is_featured_query(opts, :user_trigger_id)
    |> Sanbase.Entity.Query.maybe_filter_by_users(opts)
    |> Sanbase.Entity.Query.maybe_filter_by_cursor(:inserted_at, opts)
    |> select([ul], ul.id)
  end

  @impl Sanbase.Entity.Behaviour
  def public_and_user_entity_ids_query(user_id, opts) do
    base_entity_ids_query(opts)
    |> where([ul], ul.is_public == true or ul.user_id == ^user_id)
  end

  @impl Sanbase.Entity.Behaviour
  def public_entity_ids_query(opts) do
    base_entity_ids_query(opts)
    |> where([ul], ul.is_public == true)
  end

  @impl Sanbase.Entity.Behaviour
  def user_entity_ids_query(user_id, opts) do
    # Disable the filter by users
    opts = Keyword.put(opts, :user_ids, nil)

    base_entity_ids_query(opts)
    |> where([ul], ul.user_id == ^user_id)
  end

  # Private functions

  defp base_query() do
    from(q in __MODULE__, where: q.is_deleted != true)
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
        preload = Keyword.get(opts, :preload, @preload)
        query |> preload(^preload)
    end
  end
end
