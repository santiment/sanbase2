defmodule Sanbase.ExAdmin.Comments.Notification do
  use ExAdmin.Register

  register_resource Sanbase.Comments.Notification do
    show _ do
      attributes_table(all: true)
    end
  end
end
