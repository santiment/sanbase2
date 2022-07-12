defmodule SanbaseWeb.ExAdmin.Accounts.UserSettings do
  use ExAdmin.Register

  register_resource Sanbase.Accounts.UserSettings do
    action_items(only: [:show])
  end

  defimpl ExAdmin.Render, for: Sanbase.Accounts.Settings do
    def to_string(data) do
      data |> Map.from_struct() |> Jason.encode!()
    end
  end
end
