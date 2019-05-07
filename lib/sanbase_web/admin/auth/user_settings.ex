defmodule Sanbase.ExAdmin.Auth.UserSettings do
  use ExAdmin.Register

  alias Sanbase.Auth.UserSettings

  register_resource Sanbase.Auth.UserSettings do
    action_items(only: [:show])
  end

  defimpl ExAdmin.Render, for: Sanbase.Auth.Settings do
    def to_string(data) do
      data |> Map.from_struct() |> Jason.encode!()
    end
  end
end
