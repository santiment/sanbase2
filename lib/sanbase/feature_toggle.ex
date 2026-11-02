defmodule Sanbase.FeatureToggle do
  @moduledoc """
  On/off switches stored in the `feature_toggles` table. A toggle without a row,
  or with `enabled = false`, is off. Toggles are read from the database on every
  check, so a change (also one made with plain SQL) applies immediately.

  Toggles:
    - `disable_user_registration` - when on, no new users can be created.
      Existing users can still log in. Checked in `Sanbase.Accounts.User.create/2`.
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo

  @disable_user_registration "disable_user_registration"

  schema "feature_toggles" do
    field(:name, :string)
    field(:enabled, :boolean, default: false)

    timestamps()
  end

  def changeset(%__MODULE__{} = toggle, attrs) do
    toggle
    |> cast(attrs, [:name, :enabled])
    |> validate_required([:name, :enabled])
  end

  @spec user_registration_disabled?() :: boolean()
  def user_registration_disabled?(), do: enabled?(@disable_user_registration)

  @spec disable_user_registration() :: {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def disable_user_registration(), do: set(@disable_user_registration, true)

  @spec enable_user_registration() :: {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def enable_user_registration(), do: set(@disable_user_registration, false)

  @spec enabled?(String.t()) :: boolean()
  def enabled?(name) when is_binary(name) do
    Repo.exists?(from(t in __MODULE__, where: t.name == ^name and t.enabled))
  end

  @spec set(String.t(), boolean()) :: {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def set(name, enabled) when is_binary(name) and is_boolean(enabled) do
    %__MODULE__{}
    |> changeset(%{name: name, enabled: enabled})
    |> Repo.insert(
      on_conflict: {:replace, [:enabled, :updated_at]},
      conflict_target: :name,
      returning: true
    )
  end
end
