defmodule Sanbase.FeatureToggle do
  @moduledoc """
  On/off switches stored in the `feature_toggles` table. Toggles are read from
  the database on every check, so a change applies immediately. A toggle without
  a row has its default value.

  Toggles:
    - `user_registration` (default: enabled) - when disabled, no new users can
      be created. Existing users can still log in. Checked in
      `Sanbase.Accounts.User.create/2`.
    - `eth_registration` (default: enabled) - when disabled, a wallet address
      without an account cannot create one through wallet login. Existing
      wallet users can still log in, and the other signup paths are not
      affected. Checked in `Sanbase.Accounts.create_user_with_eth_address/1`.
    - `eth_login_legacy` (default: enabled) - when disabled, wallet login only
      accepts signatures of a one-time challenge (`ethLoginChallenge`), not the
      old fixed message, so captured old signatures stop working. Checked in
      `Sanbase.Accounts.Auth.eth_login/2`.
    - `business_reduced_api_calls` (default: disabled) - when enabled, SanAPI
      Business PRO / MAX subscriptions created after the moment it was turned on
      get the reduced monthly API call allowance; older ones keep the old one.
      The moment is stored in `enabled_at`. See
      `Sanbase.ApiCallLimit.BusinessAllowance`, which is also what to call from
      IEx: turning it off there refreshes the affected customers' limits. Change
      it only from the admin panel or IEx, never with SQL: an `UPDATE` neither
      stamps nor clears `enabled_at` and skips that refresh.

  `enabled_at` is when a toggle was last turned on, `nil` while it is off. It is
  stamped only on an actual off-to-on change, so saving an enabled toggle again
  does not move it.

  Toggle them in the admin panel (Feature Toggles), from IEx with
  `enable_user_registration/0` / `disable_user_registration/0` (and the
  `eth_registration` and `eth_login_legacy` equivalents), or with SQL (except
  `business_reduced_api_calls`, see above).
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo

  @user_registration "user_registration"
  @eth_registration "eth_registration"
  @eth_login_legacy "eth_login_legacy"
  @business_reduced_api_calls "business_reduced_api_calls"

  schema "feature_toggles" do
    field(:name, :string)
    field(:enabled, :boolean, default: false)
    field(:enabled_at, :utc_datetime)

    timestamps()
  end

  def changeset(%__MODULE__{} = toggle, attrs) do
    toggle
    |> cast(attrs, [:name, :enabled])
    |> validate_required([:name, :enabled])
    |> stamp_enabled_at()
  end

  # Used by the admin panel for edits: only `enabled` can change.
  def update_changeset(%__MODULE__{} = toggle, attrs) do
    toggle
    |> cast(attrs, [:enabled])
    |> validate_required([:enabled])
    |> stamp_enabled_at()
  end

  # Only an off-to-on change stamps the time; turning off clears it. A save that does
  # not change `enabled` leaves `enabled_at` alone.
  #
  # The column holds whole seconds, so the time is rounded up rather than truncated:
  # `enabled_at` is a cutoff, and truncating would put it up to a second before the
  # toggle was actually turned on.
  defp stamp_enabled_at(changeset) do
    case fetch_change(changeset, :enabled) do
      {:ok, true} ->
        put_change(changeset, :enabled_at, ceil_to_second(DateTime.utc_now()))

      {:ok, false} ->
        put_change(changeset, :enabled_at, nil)

      :error ->
        changeset
    end
  end

  defp ceil_to_second(%DateTime{} = datetime) do
    truncated = DateTime.truncate(datetime, :second)

    case DateTime.compare(datetime, truncated) do
      :gt -> DateTime.add(truncated, 1, :second)
      _ -> truncated
    end
  end

  @spec user_registration_enabled?() :: boolean()
  def user_registration_enabled?(), do: enabled?(@user_registration, true)

  @spec enable_user_registration() :: {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def enable_user_registration(), do: set(@user_registration, true)

  @spec disable_user_registration() :: {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def disable_user_registration(), do: set(@user_registration, false)

  @spec eth_registration_enabled?() :: boolean()
  def eth_registration_enabled?(), do: enabled?(@eth_registration, true)

  @spec enable_eth_registration() :: {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def enable_eth_registration(), do: set(@eth_registration, true)

  @spec disable_eth_registration() :: {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def disable_eth_registration(), do: set(@eth_registration, false)

  @spec eth_login_legacy_enabled?() :: boolean()
  def eth_login_legacy_enabled?(), do: enabled?(@eth_login_legacy, true)

  @spec enable_eth_login_legacy() :: {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def enable_eth_login_legacy(), do: set(@eth_login_legacy, true)

  @spec disable_eth_login_legacy() :: {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def disable_eth_login_legacy(), do: set(@eth_login_legacy, false)

  @doc """
  When `business_reduced_api_calls` was turned on, or `nil` while it is off.
  """
  @spec business_reduced_api_calls_since() :: DateTime.t() | nil
  def business_reduced_api_calls_since(), do: enabled_at(@business_reduced_api_calls)

  @spec enable_business_reduced_api_calls() ::
          {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def enable_business_reduced_api_calls(), do: set(@business_reduced_api_calls, true)

  @spec disable_business_reduced_api_calls() ::
          {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def disable_business_reduced_api_calls(), do: set(@business_reduced_api_calls, false)

  @spec business_reduced_api_calls_name() :: String.t()
  def business_reduced_api_calls_name(), do: @business_reduced_api_calls

  @doc """
  When the toggle was last turned on, or `nil` when it is off or has no row.
  """
  @spec enabled_at(String.t()) :: DateTime.t() | nil
  def enabled_at(name) when is_binary(name) do
    Repo.one(
      from(t in __MODULE__, where: t.name == ^name and t.enabled == true, select: t.enabled_at)
    )
  end

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
    # Read first so `enabled_at` is stamped only on a real off-to-on change, which an
    # upsert cannot tell apart from re-enabling an enabled toggle. The row is locked so
    # two concurrent callers turning it on serialize: the second sees it already on and
    # leaves `enabled_at` as the first one stamped it.
    Repo.transaction(fn ->
      result =
        case Repo.one(from(t in __MODULE__, where: t.name == ^name, lock: "FOR UPDATE")) do
          nil ->
            %__MODULE__{}
            |> changeset(%{name: name, enabled: enabled})
            |> Repo.insert()

          %__MODULE__{} = toggle ->
            toggle
            |> update_changeset(%{enabled: enabled})
            |> Repo.update()
        end

      case result do
        {:ok, toggle} -> toggle
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end
end
