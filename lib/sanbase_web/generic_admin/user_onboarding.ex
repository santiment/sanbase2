defmodule SanbaseWeb.GenericAdmin.UserOnboarding do
  @behaviour SanbaseWeb.GenericAdmin

  def schema_module(), do: Sanbase.Accounts.UserOnboarding
  def resource_name, do: "user_onboardings"
  def singular_resource_name, do: "user_onboarding"

  def resource do
    %{
      actions: [],
      preloads: [:user],
      index_fields: [
        :id,
        :user_id,
        :title,
        :goal,
        :used_tools,
        :uses_behaviour_analysis,
        :inserted_at,
        :updated_at
      ],
      fields_override: %{
        user_id: %{
          value_modifier: &SanbaseWeb.GenericAdmin.User.user_link/1
        },
        used_tools: %{
          value_modifier: fn row -> Enum.join(row.used_tools, ", ") end
        }
      }
    }
  end
end
