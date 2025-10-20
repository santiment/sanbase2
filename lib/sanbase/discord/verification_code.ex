defmodule Sanbase.Discord.VerificationCode do
  @moduledoc """
  Schema and functions for managing Discord verification codes.

  When a user subscribes to a paid tier, a unique verification code is generated.
  Users can use this code in Discord with the /verify command to get the PRO role.
  """

  use Ecto.Schema
  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Repo

  @type t :: %__MODULE__{}

  schema "discord_verification_codes" do
    field(:code, :string)
    field(:subscription_tier, :string)
    field(:discord_user_id, :string)
    field(:discord_username, :string)
    field(:verified_at, :utc_datetime)
    field(:expires_at, :utc_datetime)
    field(:used, :boolean, default: false)

    belongs_to(:user, Sanbase.Accounts.User)

    timestamps()
  end

  @doc """
  Generate a new verification code for a user and subscription tier.
  """
  @spec generate_code(integer(), String.t()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def generate_code(user_id, tier) do
    # Clean up any existing codes for this user
    cleanup_user_codes(user_id)

    code = generate_unique_code(tier)
    expires_at = DateTime.add(DateTime.utc_now(), expiry_days() * 24 * 60 * 60)

    %__MODULE__{}
    |> changeset(%{
      code: code,
      user_id: user_id,
      subscription_tier: tier,
      expires_at: expires_at
    })
    |> Repo.insert()
  end

  @doc """
  Verify a code and link it to a Discord user.
  """
  @spec verify_code(String.t(), String.t()) :: {:ok, t()} | {:error, atom()}
  def verify_code(code, discord_user_id) do
    query =
      from(vc in __MODULE__,
        where: vc.code == ^code
      )

    case Repo.one(query) do
      nil ->
        {:error, :invalid_code}

      verification_code ->
        # Check if already used
        if verification_code.used do
          {:error, :already_used}
          # Check if expired
        else
          if DateTime.compare(verification_code.expires_at, DateTime.utc_now()) != :gt do
            {:error, :expired}
          else
            # Get Discord username
            discord_username = get_discord_username(discord_user_id)

            verification_code
            |> changeset(%{
              discord_user_id: discord_user_id,
              discord_username: discord_username,
              verified_at: DateTime.utc_now(),
              used: true
            })
            |> Repo.update()
            |> case do
              {:ok, updated_code} -> {:ok, updated_code}
              {:error, _changeset} -> {:error, :verification_failed}
            end
          end
        end
    end
  end

  @doc """
  Get an active verification code for a specific user and tier.
  """
  @spec get_active_code(integer(), String.t()) :: t() | nil
  def get_active_code(user_id, tier) do
    query =
      from(vc in __MODULE__,
        where: vc.user_id == ^user_id,
        where: vc.subscription_tier == ^tier,
        where: vc.used == false,
        where: vc.expires_at > ^DateTime.utc_now(),
        order_by: [desc: vc.inserted_at],
        limit: 1
      )

    Repo.one(query)
  end

  @doc """
  Get any active verification code for a user (any tier).
  """
  @spec get_active_code_for_user(integer()) :: t() | nil
  def get_active_code_for_user(user_id) do
    query =
      from(vc in __MODULE__,
        where: vc.user_id == ^user_id,
        where: vc.used == false,
        where: vc.expires_at > ^DateTime.utc_now(),
        order_by: [desc: vc.inserted_at],
        limit: 1
      )

    Repo.one(query)
  end

  @doc """
  Clean up expired verification codes.
  """
  @spec cleanup_expired() :: {integer(), nil | [term()]}
  def cleanup_expired do
    query =
      from(vc in __MODULE__,
        where: vc.expires_at < ^DateTime.utc_now()
      )

    Repo.delete_all(query)
  end

  @doc """
  Delete all verification codes for a user (for testing).
  """
  @spec cleanup_user_codes(integer()) :: {integer(), nil | [term()]}
  def cleanup_user_codes(user_id) do
    query =
      from(vc in __MODULE__,
        where: vc.user_id == ^user_id
      )

    Repo.delete_all(query)
  end

  def changeset(verification_code, attrs) do
    verification_code
    |> cast(attrs, [
      :code,
      :user_id,
      :subscription_tier,
      :discord_user_id,
      :discord_username,
      :verified_at,
      :expires_at,
      :used
    ])
    |> validate_required([:code, :user_id, :subscription_tier, :expires_at])
    |> validate_length(:code, min: 1, max: 20)
    |> validate_inclusion(:subscription_tier, ["PRO", "MAX", "BUSINESS_PRO", "BUSINESS_MAX"])
    |> unique_constraint(:code)
  end

  # Private functions

  defp generate_unique_code(_tier) do
    random_part = generate_random_string(6)
    "PRO-#{random_part}"
  end

  defp generate_random_string(length) do
    chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

    for _ <- 1..length, into: "" do
      String.at(chars, :rand.uniform(String.length(chars)) - 1)
    end
  end

  defp expiry_days do
    Application.get_env(:sanbase, Sanbase.Discord, [])
    |> Keyword.get(:verification_code_expiry_days, 30)
    |> case do
      {:system, env_var, default} ->
        System.get_env(env_var, default) |> String.to_integer()

      days when is_integer(days) ->
        days

      days when is_binary(days) ->
        String.to_integer(days)

      _ ->
        30
    end
  end

  defp get_discord_username(discord_user_id) do
    # This would ideally fetch from Discord API, but for now we'll use a placeholder
    # In a real implementation, you'd call Discord API to get the username
    "user_#{String.slice(discord_user_id, -4, 4)}"
  end
end
