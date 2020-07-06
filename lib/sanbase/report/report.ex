defmodule Sanbase.Report do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo

  schema "reports" do
    field(:name, :string, null: true)
    field(:description, :string, null: true)
    field(:is_pro, :boolean, default: false)
    field(:is_published, :boolean, default: false)
    field(:url, :string)

    timestamps()
  end

  @doc false
  def changeset(report, attrs) do
    report
    |> cast(attrs, [:name, :description, :url, :is_published, :is_pro])
    |> validate_required([:url, :is_published, :is_pro])
  end

  def save(params) do
    %__MODULE__{}
    |> changeset(params)
    |> Repo.insert()
  end

  def list_published_reports(nil) do
    from(r in __MODULE__, where: r.is_published == true and r.is_pro == false)
    |> Repo.all()
  end

  def list_published_reports(_) do
    from(r in __MODULE__, where: r.is_published == true)
    |> Repo.all()
  end
end
