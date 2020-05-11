defmodule Sanbase.ExAdmin.Insight.PostComment do
  use ExAdmin.Register

  register_resource Sanbase.Insight.PostComment do
    show _ do
      attributes_table(all: true)
    end
  end
end
