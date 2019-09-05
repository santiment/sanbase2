defmodule Sanbase.ExAdmin.Model.ProjectMarketSegment do
  use ExAdmin.Register

  register_resource Sanbase.Model.Project.ProjectMarketSegment do
    show _ do
      attributes_table(all: true)
    end
  end
end
