defmodule Sanbase.Dashboard.Schema do
  @moduledoc ~s"""
  Dashboard database schema and CRUD functions for working
  with it.

  This module is used for creating and updating dashboard fields.
  It also provide functions for adding/updating/removing dashboard panels
  """

  @behaviour Sanbase.Entity.Behaviour

  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset
  import Sanbase.Utils.Transform, only: [to_bang: 1]
  import Sanbase.Utils.ErrorHandling, only: [changeset_errors_string: 1]

  alias Sanbase.Repo
  alias Sanbase.Accounts.User
  alias Sanbase.Dashboard.Panel

  @type schema_args :: %{
          optional(:name) => String.t(),
          optional(:description) => String.t(),
          optional(:is_public) => boolean(),
          optional(:user_id) => non_neg_integer()
        }

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          name: String.t(),
          description: String.t(),
          is_public: boolean(),
          parameters: Map.t(),
          panels: list(Panel.t()),
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t(),
          user: %User{}
        }

  @type panel_dashboad_map :: %{
          panel: Panel.t(),
          dashboard: t()
        }

  @type dashboard_id :: non_neg_integer()

  schema "dashboards" do
    field(:name, :string)
    field(:description, :string)
    field(:is_public, :boolean, default: false)
    field(:is_hidden, :boolean, default: false)
    field(:is_deleted, :boolean, default: false)
    field(:parameters, :map, default: %{})

    has_one(:featured_item, Sanbase.FeaturedItem,
      on_delete: :delete_all,
      foreign_key: :dashboard_id
    )

    belongs_to(:user, User)

    embeds_many(:panels, Panel, on_replace: :delete)

    # Virtual fields
    field(:views, :integer, virtual: true, default: 0)
    field(:is_featured, :boolean, virtual: true)

    timestamps()
  end

  @create_fields [:name, :description, :is_public, :parameters, :user_id]
  @update_fields @create_fields -- [:user_id]

  @impl Sanbase.Entity.Behaviour
  @spec by_id(non_neg_integer(), Keyword.t()) ::
          {:ok, t()} | {:error, String.t()}
  def by_id(dashboard_id, opts \\ []) do
    query =
      from(d in __MODULE__,
        where: d.id == ^dashboard_id
      )

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

  def is_public?(%__MODULE__{is_public: is_public}), do: is_public

  def user_dashboards(user_id) do
    query =
      from(
        ds in __MODULE__,
        where: ds.user_id == ^user_id
      )

    {:ok, Repo.all(query)}
  end

  def user_public_dashboards(user_id) do
    query =
      from(
        ds in __MODULE__,
        where: ds.user_id == ^user_id and ds.is_public == true
      )

    {:ok, Repo.all(query)}
  end

  @spec get_is_public_and_owner(non_neg_integer()) ::
          {:ok, %{user_id: non_neg_integer(), is_public: boolean()}}
          | {:error, String.t()}
  def get_is_public_and_owner(dashboard_id) do
    result =
      from(d in __MODULE__,
        where: d.id == ^dashboard_id,
        select: %{user_id: d.user_id, is_public: d.is_public}
      )
      |> Repo.one()

    case result do
      nil -> {:error, "Dashboard does not exist"}
      data -> {:ok, data}
    end
  end

  @doc ~s"""
  Create a new, empty dashboard.
  """
  @spec create(schema_args()) :: {:ok, t()} | {:error, Changeset.t()}
  def create(args) do
    %__MODULE__{}
    |> cast(args, @create_fields)
    |> validate_required([:name, :user_id])
    |> Repo.insert()
  end

  @doc ~s"""
  Update an existing dashboard

  All fields except the panels and the user_id can be updated.
  In order to update a panel use the update_panel/3 function
  """
  @spec update(dashboard_id(), schema_args()) ::
          {:ok, t()} | {:error, Changeset.t()}
  def update(dashboard_id, args) do
    {:ok, dashboard} = by_id(dashboard_id, lock_for_update: true)

    dashboard
    |> cast(args, @update_fields)
    |> Repo.update()
  end

  @doc ~s"""
  Delete a dashboard.
  """
  @spec delete(dashboard_id) :: {:ok, t()} | {:error, Changeset.t()}
  def delete(dashboard_id) do
    Repo.get(__MODULE__, dashboard_id) |> Repo.delete()
  end

  @doc ~s"""
  Add a panel to the dashboard
  """
  @spec create_panel(non_neg_integer(), Panel.panel_args() | Panel.t()) ::
          {:ok, panel_dashboad_map()} | {:error, Changeset.t()}
  def create_panel(dashboard_id, %Panel{} = panel) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:get_dashboard, fn _, _ -> by_id(dashboard_id, lock_for_update: true) end)
    |> Ecto.Multi.run(:create_panel, fn _, %{get_dashboard: dashboard} ->
      dashboard
      |> change()
      |> put_embed(:panels, [panel] ++ dashboard.panels)
      |> Repo.update()
    end)
    |> Repo.transaction()
    |> handle_panel_action_transaction_result(:create_panel, panel.id)
  end

  def create_panel(dashboard_id, panel_args) when is_map(panel_args) do
    case Panel.new(panel_args) do
      {:ok, panel} ->
        create_panel(dashboard_id, panel)

      {:error, changeset} ->
        {:error, changeset_errors_string(changeset)}
    end
  end

  @doc ~s"""
  Remove a panel from a dashboard.
  """
  @spec remove_panel(non_neg_integer(), non_neg_integer()) ::
          {:ok, panel_dashboad_map()} | {:error, Changeset.t()}
  def remove_panel(dashboard_id, panel_id) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:get_dashboard, fn _, _ -> by_id(dashboard_id, lock_for_update: true) end)
    |> Ecto.Multi.run(:remove_panel, fn _, %{get_dashboard: dashboard} ->
      with {[panel], panels} <- Enum.split_with(dashboard.panels, &(&1.id == panel_id)),
           %Ecto.Changeset{} = changeset <- dashboard |> change() |> put_embed(:panels, panels),
           {:ok, dashboard} <- Repo.update(changeset) do
        {:ok, %{dashboard: dashboard, panel: panel}}
      else
        {[], _panels} ->
          {:error, "Dashboard #{dashboard_id} does not have a panel panel with id #{panel_id}."}

        {:error, error} ->
          {:error, error}
      end
    end)
    |> Repo.transaction()
    |> handle_panel_action_transaction_result(:remove_panel, panel_id)
  end

  @doc ~s"""
  Update a panel on a dashboard.
  This operation preserves the panel id.
  """
  @spec update_panel(non_neg_integer(), non_neg_integer(), Panel.panel_args()) ::
          {:ok, panel_dashboad_map()}
          | {:error, :dashboard_panel_does_not_exist}
  def update_panel(dashboard_id, panel_id, panel_args) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:get_dashboard, fn _, _ -> by_id(dashboard_id, lock_for_update: true) end)
    |> Ecto.Multi.run(:update_panel, fn _, %{get_dashboard: dashboard} ->
      with {[panel], panels} <- Enum.split_with(dashboard.panels, &(&1.id == panel_id)),
           {:ok, updated_panel} <- Panel.update(panel, panel_args, as_changeset: true) do
        dashboard
        |> change()
        |> put_embed(:panels, [updated_panel] ++ panels)
        |> Repo.update()
      else
        {[], _panels} ->
          {:error, "Dashboard #{dashboard_id} does not have a panel panel with id #{panel_id}."}

        {:error, error} ->
          {:error, error}
      end
    end)
    |> Repo.transaction()
    |> handle_panel_action_transaction_result(:update_panel, panel_id)
  end

  # Private functions

  defp base_query() do
    from(conf in __MODULE__, where: conf.is_deleted != true)
  end

  defp handle_panel_action_transaction_result(result_tuple, action, panel_id)
       when action in [:create_panel, :update_panel, :remove_panel] do
    case result_tuple do
      # In case of :remove_panel, the result already contains the panel and dashboard.
      # This is because the panel cannot be found with Enum.find as it's already
      # removed from the panels list.
      {:ok, %{^action => %{dashboard: _, panel: _} = result}} ->
        {:ok, result}

      {:ok, %{^action => %__MODULE__{} = dashboard}} ->
        panel = Enum.find(dashboard.panels, &(&1.id == panel_id))
        {:ok, %{dashboard: dashboard, panel: panel}}

      {:error, _failed_op, %Ecto.Changeset{} = changeset, _changes} ->
        {:error, changeset_errors_string(changeset)}

      {:error, _failed_op, error, _changes} ->
        {:error, error}
    end
  end
end
