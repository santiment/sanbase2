defmodule Sanbase.Queries.ExternalData do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  schema "queries_external_data" do
    field(:uuid, :string)

    field(:name, :string)
    field(:description, :string)

    field(:storage, :string)
    field(:location, :string)

    belongs_to(:user, Sanbase.Accounts.User)

    timestamps()
  end

  def changeset(%__MODULE__{} = qel, attrs) do
    qel
    |> cast(attrs, [:name, :description, :storage, :uuid, :location, :user_id])
    |> validate_required([:name, :storage, :uuid, :location, :user_id])
    |> unique_constraint([:user_id, :name])
    |> unique_constraint(:uuid)
  end

  def get_path(%__MODULE__{user_id: user_id, name: name}), do: "/user/#{user_id}/#{name}"

  def resolve_path(path) do
    case String.split(path, "/", trim: true) do
      ["user", user_id, file_name] ->
        get_file_data(user_id, file_name)

      # If we want to have some global?
      # ["global", file_name] ->
      #   get_file_data(file_name)

      _parts ->
        {:error, "Malformed path: #{path}"}
    end
  end

  def get_file_data(user_id, file_name) do
    query =
      from(qel in __MODULE__,
        where: qel.user_id == ^user_id and qel.name == ^file_name
      )

    case Sanbase.Repo.one(query) do
      nil -> {:error, "Record for external data source not found"}
      %__MODULE__{} = struct -> {:ok, struct}
    end
  end

  def store(name, user_id, data) when is_map(data) or is_list(data) do
    uuid = UUID.uuid4()
    filename = "#{uuid}-#{name}"
    data_json = Jason.encode!(data)

    with {:ok, file} <-
           Sanbase.Queries.ExternalData.Store.store(%{binary: data_json, filename: filename}) do
      url = Sanbase.Queries.ExternalData.Store.url(file)

      %__MODULE__{}
      |> changeset(%{
        name: name,
        uuid: uuid,
        user_id: user_id,
        storage: get_storage(),
        location: url
      })
      |> Sanbase.Repo.insert()
    end
  end

  def get(%__MODULE__{} = struct) do
    result =
      case struct do
        %{storage: "s3"} ->
          __MODULE__.Store.get_s3(struct.location)

        %{storage: "local"} ->
          __MODULE__.Store.get_local(struct.location)
      end

    case result do
      {:ok, json} -> {:ok, Jason.decode!(json)}
      {:error, error} -> {:error, error}
    end
  end

  defp get_storage() do
    case Application.get_env(:waffle, :storage) do
      Waffle.Storage.Local -> "local"
      Waffle.Storage.S3 -> "s3"
    end
  end
end
