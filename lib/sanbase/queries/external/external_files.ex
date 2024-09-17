defmodule Sanbase.Queries.ExternalFiles do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  schema "queries_external_files" do
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

  def resolve_path(path) do
    case String.split(path, "/") do
      ["user", user_id, file_name] ->
        get_file_data(user_id, file_name)

      # ["global", file_name] ->
      #   get_file_data(file_name)

      _ ->
        {:error, "Malformed path: #{path}"}
    end
  end

  def get_file_data(user_id, file_name) do
    query =
      from(qel in __MODULE__,
        where: qel.user_id == ^user_id and qel.name == ^file_name
      )

    case Sanbase.Repo.one(query) do
      nil -> {:error, "File not found"}
      %__MODULE__{} = struct -> {:ok, struct}
    end
  end

  def store(name, user_id, data) do
    filename = "#{UUID.uuid4()}-#{name}"
    data = data |> :zlib.gzip() |> Base.encode64()

    with url <- Sanbase.FileStore.store(%{binary: data, filename: filename}) do
      %__MODULE__{}
      |> changeset(%{name: name, user_id: user_id, storage: "s3", location: url})
      |> Sanbase.Repo.insert()
    end
  end

  def get(%__MODULE__{} = struct) do
    case struct do
      %{storage: "s3"} ->
        # __MODULE__.S3.get(struct)
        {:ok, []}
    end
  end
end
