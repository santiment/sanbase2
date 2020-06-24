defmodule SanbaseWeb.ExAdmin.Intercom.UserAttributes do
  use ExAdmin.Register

  register_resource Sanbase.Intercom.UserAttributes do
    action_items(only: [:show])

    index do
      column(:user, link: true)
    end

    show configuration do
      attributes_table do
        row(:user, link: true)
        row(:properties)
      end
    end
  end
end
