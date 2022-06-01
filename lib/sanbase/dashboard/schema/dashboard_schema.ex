defmodule Sanbase.Dashboard.Schema do
  @moduledoc ~s"""
  Dashboard database schema and CRUD functions for working
  with it.

  This module is used for creating and updating dashboard fields.
  It also provide functions for adding/updating/removing dashboard panels
  """

  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Accounts.User
  alias Sanbase.Dashboard.Panel

  @type schema_args :: %{
          name: String.t(),
          description: String.t(),
          is_public: boolean(),
          user_id: non_neg_integer()
        }

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          name: String.t(),
          description: String.t(),
          is_public: boolean(),
          panels: list(Panel.t()),
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t(),
          user: %User{}
        }

  @type dashboard_id :: non_neg_integer()

  schema "dashboards" do
    field(:name, :string)
    field(:description, :string)
    field(:is_public, :boolean, default: false)

    belongs_to(:user, User)

    embeds_many(:panels, Panel, on_replace: :delete)

    timestamps()
  end

  @spec by_id(non_neg_integer()) :: {:ok, t()} | {:error, String.t()}
  def by_id(dashboard_id) do
    case Sanbase.Repo.get(__MODULE__, dashboard_id) do
      %__MODULE__{} = dashboard -> {:ok, dashboard}
      nil -> {:error, "Dashboard does not exist"}
    end
  end

  @spec get_is_public_and_owner(non_neg_integer()) ::
          {:ok, %{user_id: non_neg_integer(), is_public: boolean()}} | {:error, String.t()}
  def get_is_public_and_owner(dashboard_id) do
    result =
      from(d in __MODULE__,
        where: d.id == ^dashboard_id,
        select: %{user_id: d.user_id, is_public: d.is_public}
      )
      |> Sanbase.Repo.one()

    case result do
      nil -> {:error, "Dashboard does not exist"}
      data -> {:ok, data}
    end
  end

  @doc ~s"""
  Create a new, empty dashboard.
  """
  @spec new(schema_args()) :: {:ok, t()} | {:error, Changeset.t()}
  def new(args) do
    %__MODULE__{}
    |> cast(args, [:name, :description, :is_public, :user_id])
    |> validate_required([:name, :user_id])
    |> Sanbase.Repo.insert()
  end

  @doc ~s"""
  Update an existing dashboard

  All fields except the panels and the user_id can be updated.
  In order to update a panel use the update_panel/3 function
  """
  @spec update(dashboard_id(), schema_args()) :: {:ok, t()} | {:error, Changeset.t()}
  def update(dashboard_id, args) do
    {:ok, dashboard} = by_id(dashboard_id)

    dashboard
    |> cast(args, [:name, :description, :is_public])
    |> Sanbase.Repo.update()
  end

  @doc ~s"""
  Add a panel to the dashboard
  """
  @spec add_panel(non_neg_integer(), Panel.panel_args() | Panel.t()) ::
          {:ok, t()} | {:error, Changeset.t()}
  def add_panel(dashboard_id, %Panel{} = panel) do
    {:ok, dashboard} = by_id(dashboard_id)

    dashboard
    |> change()
    |> put_embed(:panels, [panel] ++ dashboard.panels)
    |> Sanbase.Repo.update()
  end

  def add_panel(dashboard_id, panel_args) when is_map(panel_args) do
    {:ok, panel} = Panel.new(panel_args)
    add_panel(dashboard_id, panel)
  end

  @doc ~s"""
  Remove a panel from a dashboard.
  """
  @spec remove_panel(non_neg_integer(), non_neg_integer()) ::
          {:ok, t()} | {:error, Changeset.t()}
  def remove_panel(dashboard_id, panel_id) do
    {:ok, dashboard} = by_id(dashboard_id)
    panels = Enum.reject(dashboard.panels, &(&1.id == panel_id))

    dashboard
    |> change()
    |> put_embed(:panels, panels)
    |> Sanbase.Repo.update()
  end

  @doc ~s"""
  Update a panel on a dashboard.
  This operation preserves the panel id.
  """
  @spec update_panel(non_neg_integer(), non_neg_integer(), Panel.panel_args()) ::
          {:ok, t()} | {:error, :dashboard_panel_does_not_exist}
  def update_panel(dashboard_id, panel_id, panel_args) do
    {:ok, dashboard} = by_id(dashboard_id)

    case Enum.find(dashboard.panels, &(&1.id == panel_id)) do
      nil ->
        {:error, :dashboard_panel_does_not_exist}

      panel ->
        {:ok, panel} = Panel.update(panel, panel_args)

        # Atomically remove and add the panel to simulate update.
        # Either both succeed or neither of them does. This guards against
        # removing the panel and failing to add it back.
        Ecto.Multi.new()
        |> Ecto.Multi.run(:remove_panel, fn _, _ -> remove_panel(dashboard_id, panel_id) end)
        |> Ecto.Multi.run(:add_panel, fn _, _ -> add_panel(dashboard_id, panel) end)
        |> Sanbase.Repo.transaction()
        |> case do
          {:ok, %{add_panel: result}} -> {:ok, result}
          {:error, _failed_op, error, _changes} -> {:error, error}
        end
    end
  end
end
