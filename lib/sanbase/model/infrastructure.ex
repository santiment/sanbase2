defmodule Sanbase.Model.Infrastructure do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false

  alias Sanbase.Repo

  alias Sanbase.Project
  alias Sanbase.Model.Infrastructure

  schema "infrastructures" do
    field(:code, :string)
    has_many(:projects, Project)
  end

  @doc false
  def changeset(%Infrastructure{} = infrastructure, attrs \\ %{}) do
    infrastructure
    |> cast(attrs, [:code])
    |> validate_required([:code])
    |> unique_constraint(:code)
  end

  def get(infrastructure_real_code) do
    Repo.get_by(Infrastructure, code: infrastructure_real_code)
  end

  def insert!(infrastructure_real_code) do
    %Infrastructure{}
    |> Infrastructure.changeset(%{code: infrastructure_real_code})
    |> Repo.insert!()
  end

  def get_or_insert(infrastructure_real_code) do
    {:ok, infrastructure} =
      Repo.transaction(fn ->
        get(infrastructure_real_code)
        |> case do
          nil -> insert!(infrastructure_real_code)
          infrastructure -> infrastructure
        end
      end)

    infrastructure
  end

  def by_code(code) when is_binary(code) do
    case Repo.get_by(__MODULE__, code: code) do
      %__MODULE__{} = infr -> {:ok, infr}
      nil -> {:error, "No infrastructure with code #{code} exists."}
    end
  end

  def by_codes(codes) when is_list(codes) do
    from(infr in __MODULE__, where: infr.code in ^codes)
    |> Repo.all()
  end

  def by_ids(ids) when is_list(ids) do
    from(inf in __MODULE__,
      where: inf.id in ^ids
    )
    |> Repo.all()
  end
end
