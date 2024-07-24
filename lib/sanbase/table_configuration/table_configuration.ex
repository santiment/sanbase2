defmodule Sanbase.TableConfiguration do
  use Ecto.Schema

  import Ecto.{Query, Changeset}

  alias Sanbase.Repo

  schema "table_configurations" do
    field(:type, TableConfigurationType)
    field(:title, :string)
    field(:description, :string)
    field(:is_public, :boolean, default: false)
    field(:page_size, :integer, default: 50)
    field(:columns, :map, default: %{})

    has_one(:featured_item, Sanbase.FeaturedItem,
      on_delete: :delete_all,
      foreign_key: :table_configuration_id
    )

    belongs_to(:user, Sanbase.Accounts.User)

    has_many(:watchlists, Sanbase.UserList)

    timestamps()
  end

  @fields [:user_id, :type, :title, :description, :is_public, :page_size, :columns]
  def changeset(%__MODULE__{} = table_configuration, attrs \\ %{}) do
    table_configuration
    |> cast(attrs, @fields)
    |> validate_required([:user_id, :title])
  end

  def update_changeset(%__MODULE__{} = table_configuration, attrs \\ %{}) do
    table_configuration
    |> cast(attrs, @fields)
  end

  def by_id(table_configuration_id, querying_user_id \\ nil) do
    get_table_configuration(table_configuration_id, querying_user_id)
  end

  def public?(%__MODULE__{is_public: is_public}), do: is_public

  def user_table_configurations(user_id, querying_user_id) do
    user_table_configurations_query(user_id, querying_user_id)
    |> Repo.all()
  end

  def table_configurations(querying_user_id \\ nil) do
    __MODULE__
    |> accessible_by_user_query(querying_user_id)
    |> Repo.all()
  end

  def create(%{} = attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  def update(table_configuration_id, user_id, attrs) do
    case get_table_configuration_if_owner(table_configuration_id, user_id) do
      {:ok, %__MODULE__{} = conf} ->
        conf
        |> update_changeset(attrs)
        |> Repo.update()

      {:error, error} ->
        {:error, "Cannot update table configuration. Reason: #{inspect(error)}"}
    end
  end

  def delete(table_configuration_id, user_id) do
    case get_table_configuration_if_owner(table_configuration_id, user_id) do
      {:ok, %__MODULE__{} = conf} ->
        conf
        |> Repo.delete()

      {:error, error} ->
        {:error, "Cannot delete table configuration. Reason: #{inspect(error)}"}
    end
  end

  defp get_table_configuration(table_configuration_id, querying_user_id) do
    case Repo.get(__MODULE__, table_configuration_id) do
      %__MODULE__{user_id: user_id, is_public: is_public} = conf
      when user_id == querying_user_id or is_public == true ->
        {:ok, conf}

      %__MODULE__{} ->
        {:error, "table configuration with id #{table_configuration_id} is private."}

      nil ->
        {:error, "table configuration with id #{table_configuration_id} does not exist."}
    end
  end

  defp get_table_configuration_if_owner(table_configuration_id, user_id) do
    case Repo.get(__MODULE__, table_configuration_id) do
      %__MODULE__{user_id: ^user_id} = conf ->
        {:ok, conf}

      %__MODULE__{} ->
        {:error,
         "table configuration with id #{table_configuration_id} is not owned by the user with id #{user_id}"}

      nil ->
        {:error, "table configuration with id #{table_configuration_id} does not exist."}
    end
  end

  defp user_table_configurations_query(user_id, querying_user_id) do
    __MODULE__
    |> where([conf], conf.user_id == ^user_id)
    |> accessible_by_user_query(querying_user_id)
  end

  defp accessible_by_user_query(query, nil) do
    query
    |> where([conf], conf.is_public == true)
  end

  defp accessible_by_user_query(query, querying_user_id) do
    query
    |> where([conf], conf.is_public == true or conf.user_id == ^querying_user_id)
  end
end
