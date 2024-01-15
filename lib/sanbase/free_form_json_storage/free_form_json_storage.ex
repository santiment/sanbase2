defmodule Sanbase.FreeFormJsonStorage do
  @moduledoc ~s"""
  There is a CRUD API for storing JSON objects in the database.
  It is accsessible only to users with @santiment.net email.
  It is used by the FE team for POCs and experiments, so they have a
  permanent storage for their data before the backend creates a specific
  API for it.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Sanbase.Utils.ErrorHandling, only: [changeset_errors_string: 1]

  schema "free_form_json_storage" do
    field(:key, :string)
    field(:value, :map)

    timestamps()
  end

  def get(key) do
    case Sanbase.Repo.get_by(__MODULE__, key: key) do
      nil -> {:error, "Key #{key} not found"}
      %__MODULE__{} = storage -> {:ok, storage}
    end
  end

  def create(key, value) do
    result =
      %__MODULE__{}
      |> cast(%{key: key, value: value}, [:key, :value])
      |> validate_required([:key, :value])
      |> unique_constraint(:key)
      |> Sanbase.Repo.insert()

    case result do
      {:ok, _} -> result
      {:error, changeset} -> {:error, changeset_errors_string(changeset)}
    end
  end

  def update(key, value) do
    with {:ok, struct} <- get(key) do
      result =
        struct
        |> Ecto.Changeset.change(value: value)
        |> Sanbase.Repo.update()

      case result do
        {:ok, _} -> result
        {:error, changeset} -> {:error, changeset_errors_string(changeset)}
      end
    end
  end

  def delete(key) do
    with {:ok, struct} <- get(key) do
      Sanbase.Repo.delete(struct)
    end
  end
end
