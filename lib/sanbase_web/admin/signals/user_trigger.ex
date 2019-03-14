defmodule Sanbase.ExAdmin.Signals.UserTrigger do
  use ExAdmin.Register

  import Ecto.Query, warn: false

  register_resource Sanbase.Signals.UserTrigger do
    action_items(only: [:show])

    index do
      column(:id)
      column(:user)
      column(:trigger, &Jason.encode!(&1.trigger |> Map.from_struct()))
    end

    show historical_activity do
      # attributes_table()

      # table_for Sanbase.Repo.preload(historical_activity, [:featured_item]) do
      #   column(:id)
      #   column(:user, link: true)
      #   column(:trigger, &Jason.encode!(&1.trigger |> Map.from_struct()))
      # end
    end
  end
end
