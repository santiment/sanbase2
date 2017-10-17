defmodule Sanbase.Model.Btt do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.Btt
  alias Sanbase.Model.Project


  schema "btt" do
    field :date, :date
    field :link, :string
    field :post_until_icoend, :integer
    field :post_until_icostart, :integer
    field :posts_total, :integer
    field :total_reads, :integer
    belongs_to :project, Project
  end

  @doc false
  def changeset(%Btt{} = btt, attrs \\ %{}) do
    btt
    |> cast(attrs, [:link, :date, :total_reads, :post_until_icostart, :post_until_icoend, :posts_total])
    |> validate_required([:link, :date, :total_reads, :post_until_icostart, :post_until_icoend, :posts_total])
    |> unique_constraint(:project_id)
  end
end
