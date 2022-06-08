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
  import Sanbase.Utils.Transform, only: [maybe_apply_function: 2]

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

  @type panel_dashboad_map :: %{
          panel: Panel.t(),
          dashboard: t()
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
  @spec create(schema_args()) :: {:ok, t()} | {:error, Changeset.t()}
  def create(args) do
    %__MODULE__{}
    |> cast(args, [:name, :description, :is_public, :user_id])
    |> validate_required([:name, :user_id])
    |> Sanbase.Repo.insert()
  end

  @doc ~s"""
  Delete a dashboard.
  """
  @spec delete(dashboard_id) :: {:ok, t()} | {:error, Changeset.t()}
  def delete(dashboard_id) do
    Sanbase.Repo.get(__MODULE__, dashboard_id) |> Sanbase.Repo.delete()
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
  @spec create_panel(non_neg_integer(), Panel.panel_args() | Panel.t()) ::
          {:ok, panel_dashboad_map()} | {:error, Changeset.t()}
  def create_panel(dashboard_id, %Panel{} = panel) do
    {:ok, dashboard} = by_id(dashboard_id)

    dashboard
    |> change()
    |> put_embed(:panels, dashboard.panels ++ [panel])
    |> Sanbase.Repo.update()
    |> maybe_apply_function(fn dashboard ->
      %{panel: panel, dashboard: dashboard}
    end)
  end

  def create_panel(dashboard_id, panel_args) when is_map(panel_args) do
    case Panel.new(panel_args) do
      {:ok, panel} ->
        create_panel(dashboard_id, panel)

      {:error, changeset} ->
        {:error, Sanbase.Utils.ErrorHandling.changeset_errors_string(changeset)}
    end
  end

  @doc ~s"""
  Remove a panel from a dashboard.
  """
  @spec remove_panel(non_neg_integer(), non_neg_integer()) ::
          {:ok, panel_dashboad_map()} | {:error, Changeset.t()}
  def remove_panel(dashboard_id, panel_id) do
    with {:ok, dashboard} <- by_id(dashboard_id),
         {[panel], panels_left} <- Enum.split_with(dashboard.panels, &(&1.id == panel_id)) do
      dashboard
      |> change()
      |> put_embed(:panels, panels_left)
      |> Sanbase.Repo.update()
      |> maybe_apply_function(fn dashboard ->
        %{panel: panel, dashboard: dashboard}
      end)
    else
      _ -> {:error, "Failed removing a panel"}
    end
  end

  @doc ~s"""
  Update a panel on a dashboard.
  This operation preserves the panel id.
  """
  @spec update_panel(non_neg_integer(), non_neg_integer(), Panel.panel_args()) ::
          {:ok, panel_dashboad_map()} | {:error, :dashboard_panel_does_not_exist}
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
        |> Ecto.Multi.run(:create_panel, fn _, _ -> create_panel(dashboard_id, panel) end)
        |> Sanbase.Repo.transaction()
        |> case do
          {:ok, %{create_panel: result}} -> {:ok, result}
          {:error, _failed_op, error, _changes} -> {:error, error}
        end
    end
  end
end
