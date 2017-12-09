defmodule Sanbase.Model.Infrastructure do
  use Ecto.Schema
  import Ecto.Changeset

  import Ecto.Query, warn: false
  alias Sanbase.Repo

  alias Sanbase.Model.Infrastructure
  alias Sanbase.Model.Project

  schema "infrastructures" do
    field :code, :string
    has_many :projects, Project
  end

  @doc false
  def changeset(%Infrastructure{} = infrastructure, attrs \\ %{}) do
    infrastructure
    |> cast(attrs, [:code])
    |> validate_required([:code])
    |> unique_constraint(:code)
  end

  def get(infrastructure_code) do
    Repo.get_by(Infrastructure, code: infrastructure_code)
  end

  def insert!(infrastructure_code) do
    %Infrastructure{}
    |> Infrastructure.changeset(%{code: infrastructure_code})
    |> Repo.insert!()
  end

  def get_or_insert(infrastructure_code) do
    {:ok, infrastructure} = Repo.transaction(fn ->
      get(infrastructure_code)
      |> case do
        nil -> insert!(infrastructure_code)
        infrastructure -> infrastructure
      end
    end)

    infrastructure
  end
end
