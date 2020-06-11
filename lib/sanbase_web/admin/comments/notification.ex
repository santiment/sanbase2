defmodule Sanbase.ExAdmin.Comments.Notification do
  use ExAdmin.Register

  register_resource Sanbase.Comments.Notification do
    show notif do
      attributes_table(all: true)
    end
  end
end
