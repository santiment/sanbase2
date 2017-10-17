defmodule Sanbase.Model.Infrastructure do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.Infrastructure
  alias Sanbase.Model.Project


  @primary_key{:code, :string, []}
  schema "infrastructures" do
    # field :code, :string
    has_many :projects, Project
  end

  @doc false
  def changeset(%Infrastructure{} = infrastructure, attrs \\ %{}) do
    infrastructure
    |> cast(attrs, [:code])
    |> validate_required([:code])
  end
end
