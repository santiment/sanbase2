defmodule Sanbase.ExAdmin.Insight.Comment do
  use ExAdmin.Register

  register_resource Sanbase.Insight.Comment do
    show _ do
      attributes_table(all: true)
    end
  end
end
