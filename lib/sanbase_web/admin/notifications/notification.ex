defmodule Sanbase.ExAdmin.Notifications.Notification do
  use ExAdmin.Register

  register_resource Sanbase.Notifications.Notification do
    show _notification do
      attributes_table(all: true)
    end
  end
end
