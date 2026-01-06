defmodule SanbaseWeb.GenericAdmin.DiscordVerificationCode do
  def schema_module, do: Sanbase.Discord.VerificationCode

  def resource() do
    %{
      actions: [:show],
      fields_override: %{
        discord_username: %{
          label: "Discord Username"
        },
        discord_user_id: %{
          label: "Discord User ID"
        }
      }
    }
  end
end
