defmodule SanbaseWeb.ExAdmin.Intercom.UserAttributes do
  use ExAdmin.Register

  register_resource Sanbase.Intercom.UserAttributes do
    action_items(only: [:show])

    index do
      column(:user, link: true)
      column(:inserted_at)
    end

    show user_attributes do
      attributes_table do
        row(:user, link: true)
        row(:inserted_at)
        row(:properties)
      end
    end
  end
end
