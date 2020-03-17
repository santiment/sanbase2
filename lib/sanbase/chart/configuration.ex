defmodule Sanbase.Chart.Configuration do
  use Ecto.Schema

  import Ecto.{Query, Changeset}

  alias Sanbase.Repo

  schema "chart_configurations" do
    field(:title, :string)
    field(:description, :string)
    field(:is_public, :boolean, default: false)

    field(:metrics, {:array, :string}, default: [])
    field(:anomalies, {:array, :string}, default: [])
    field(:drawings, :map, default: %{})

    belongs_to(:user, Sanbase.Auth.User)
    belongs_to(:project, Sanbase.Model.Project)

    timestamps()
  end

  def changeset(%__MODULE__{} = conf, attrs \\ %{}) do
    conf
    |> cast(attrs, [
      :title,
      :description,
      :is_public,
      :metrics,
      :anomalies,
      :drawings,
      :user_id,
      :project_id
    ])
    |> validate_required([:user_id, :project_id])
  end

  def by_id(config_id, querying_user_id \\ nil) do
    get_chart_configuration(config_id, querying_user_id)
  end

  def user_configurations(user_id, querying_user_id, project_id \\ nil) do
    user_chart_configurations_query(user_id, querying_user_id, project_id)
    |> Repo.all()
  end

  def project_configurations(project_id, querying_user_id \\ nil) do
    project_chart_configurations_query(project_id, querying_user_id)
    |> Repo.all()
  end

  def configurations(querying_user_id \\ nil) do
    configurations_query(querying_user_id)
    |> Repo.all()
  end

  def create(%{} = attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  def update(config_id, user_id, attrs) do
    case get_chart_configuration_if_owner(config_id, user_id) do
      {:ok, %__MODULE__{} = conf} ->
        conf
        |> changeset(attrs)
        |> Repo.update()

      {:error, error} ->
        {:error, "Cannot update chart configuration. Reason: #{inspect(error)}"}
    end
  end

  def delete(config_id, user_id) do
    case get_chart_configuration_if_owner(config_id, user_id) do
      {:ok, %__MODULE__{} = conf} ->
        conf
        |> Repo.delete()

      {:error, error} ->
        {:error, "Cannot delete chart configuration. Reason: #{inspect(error)}"}
    end
  end

  defp get_chart_configuration(config_id, querying_user_id) do
    case from(conf in __MODULE__, where: conf.id == ^config_id) |> Repo.one() do
      %__MODULE__{user_id: user_id, is_public: is_public} = conf
      when user_id == querying_user_id or is_public == true ->
        {:ok, conf}

      %__MODULE__{} ->
        {:error, "Chart configuration with id #{config_id} is private."}

      nil ->
        {:error, "Chart configuration with id #{config_id} does not exist."}
    end
  end

  defp get_chart_configuration_if_owner(config_id, user_id) do
    case from(conf in __MODULE__, where: conf.id == ^config_id) |> Repo.one() do
      %__MODULE__{user_id: ^user_id} = conf ->
        {:ok, conf}

      %__MODULE__{} ->
        {:error,
         "Chart configuration with id #{config_id} is not owned by the user with id #{user_id}"}

      nil ->
        {:error, "Chart configuration with id #{config_id} does not exist."}
    end
  end

  defp all_user_configurations_query(user_id, querying_user_id) do
    from(
      conf in __MODULE__,
      where:
        conf.user_id == ^user_id and
          (conf.user_id == ^querying_user_id or conf.is_public == true)
    )
  end

  defp user_chart_configurations_query(user_id, querying_user_id, nil) do
    all_user_configurations_query(user_id, querying_user_id)
  end

  defp user_chart_configurations_query(user_id, querying_user_id, project_id) do
    from(
      conf in __MODULE__,
      where:
        conf.user_id == ^user_id and conf.project_id == ^project_id and
          (conf.user_id == ^querying_user_id or conf.is_public == true)
    )
  end

  defp project_chart_configurations_query(project_id, querying_user_id) do
    from(
      conf in __MODULE__,
      where:
        conf.project_id == ^project_id and
          (conf.user_id == ^querying_user_id or conf.is_public == true)
    )
  end

  defp configurations_query(nil) do
    from(conf in __MODULE__, where: conf.is_public == true)
  end

  defp configurations_query(querying_user_id) do
    from(conf in __MODULE__, where: conf.is_public == true or conf.user_id == ^querying_user_id)
  end
end
