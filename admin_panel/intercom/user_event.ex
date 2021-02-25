defmodule SanbaseWeb.ExAdmin.Intercom.UserEvent do
  use ExAdmin.Register

  register_resource Sanbase.Intercom.UserEvent do
    action_items(only: [:show])

    show user_event do
      attributes_table(all: true)
    end
  end
end
