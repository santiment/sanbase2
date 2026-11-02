defmodule Sanbase.FeatureToggle do
  @moduledoc """
  On/off switches stored in the `feature_toggles` table. Toggles are read from
  the database on every check, so a change (also one made with plain SQL)
  applies immediately. A toggle without a row has its default value.

  Toggles:
    - `user_registration` (default: enabled) - when disabled, no new users can
      be created. Existing users can still log in. Checked in
      `Sanbase.Accounts.User.create/2`.

  Toggle them in the admin panel (Feature Toggles), from IEx with
  `enable_user_registration/0` / `disable_user_registration/0`, or with SQL.
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo

  @user_registration "user_registration"

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

  # Used by the admin panel for edits: only `enabled` can change.
  def update_changeset(%__MODULE__{} = toggle, attrs) do
    toggle
    |> cast(attrs, [:enabled])
    |> validate_required([:enabled])
  end

  @spec user_registration_enabled?() :: boolean()
  def user_registration_enabled?(), do: enabled?(@user_registration, true)

  @spec enable_user_registration() :: {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def enable_user_registration(), do: set(@user_registration, true)

  @spec disable_user_registration() :: {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def disable_user_registration(), do: set(@user_registration, false)

  @doc """
  Whether the toggle is enabled. Returns `default` when the toggle has no row.
  """
  @spec enabled?(String.t(), boolean()) :: boolean()
  def enabled?(name, default) when is_binary(name) and is_boolean(default) do
    case Repo.one(from(t in __MODULE__, where: t.name == ^name, select: t.enabled)) do
      nil -> default
      enabled -> enabled
    end
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
