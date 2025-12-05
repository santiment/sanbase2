defmodule Sanbase.Discord do
  @moduledoc """
  Context module for Discord-related functionality.
  """

  alias Sanbase.Discord.VerificationCode

  @doc """
  Get verification information for a user.
  Returns nil if no active verification code exists.
  """
  @spec get_verification_info(integer()) :: map() | nil
  def get_verification_info(user_id) do
    case VerificationCode.get_active_code_for_user(user_id) do
      nil ->
        nil

      verification_code ->
        %{
          code: verification_code.code,
          invite_url: discord_invite_url(),
          verified: verification_code.verified_at != nil,
          tier: verification_code.subscription_tier,
          discord_username: verification_code.discord_username
        }
    end
  end

  @doc """
  Get the configured Discord invite URL.
  """
  @spec discord_invite_url() :: String.t()
  def discord_invite_url do
    Application.get_env(:sanbase, Sanbase.Discord, [])
    |> Keyword.get(:invite_url, "https://discord.gg/EJrZR8GHZU")
    |> case do
      {:system, env_var, default} -> System.get_env(env_var, default)
      url when is_binary(url) -> url
      _ -> "https://discord.gg/EJrZR8GHZU"
    end
  end
end
