defmodule Sanbase.Email.EmailExclusionList do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          email: String.t(),
          reason: String.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "email_exclusion_list" do
    field(:email, :string)
    field(:reason, :string)

    timestamps()
  end

  @doc """
  Creates a changeset for the email exclusion list entry.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(email_exclusion \\ %__MODULE__{}, attrs) do
    email_exclusion
    |> cast(attrs, [:email, :reason])
    |> validate_required([:email])
    |> validate_format(:email, ~r/@/)
    |> unique_constraint(:email)
  end

  @doc """
  Checks if an email is in the exclusion list.
  """
  @spec is_excluded?(String.t()) :: boolean()
  def is_excluded?(email) when is_binary(email) do
    from(e in __MODULE__, where: e.email == ^email)
    |> Repo.exists?()
  end

  def is_excluded?(_), do: false

  @doc """
  Adds an email to the exclusion list.
  """
  @spec add_exclusion(String.t(), String.t() | nil) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def add_exclusion(email, reason \\ nil) do
    %__MODULE__{}
    |> changeset(%{email: email, reason: reason})
    |> Repo.insert()
  end

  @doc """
  Removes an email from the exclusion list.
  """
  @spec remove_exclusion(String.t()) :: {:ok, t()} | {:error, :not_found}
  def remove_exclusion(email) do
    case Repo.get_by(__MODULE__, email: email) do
      nil -> {:error, :not_found}
      exclusion -> Repo.delete(exclusion)
    end
  end

  @doc """
  Gets all excluded emails.
  """
  @spec list_exclusions() :: [t()]
  def list_exclusions do
    Repo.all(__MODULE__)
  end

  @doc """
  Gets an exclusion entry by ID.
  """
  @spec get_exclusion(integer()) :: t() | nil
  def get_exclusion(id) do
    Repo.get(__MODULE__, id)
  end

  @doc """
  Updates an exclusion entry.
  """
  @spec update_exclusion(t(), map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def update_exclusion(exclusion, attrs) do
    exclusion
    |> changeset(attrs)
    |> Repo.update()
  end
end
