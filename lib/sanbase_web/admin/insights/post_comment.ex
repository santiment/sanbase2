defmodule Sanbase.ExAdmin.Insight.PostComment do
  use ExAdmin.Register

  register_resource Sanbase.Insight.PostComment do
    show post_comment do
      attributes_table(all: true)
    end
  end
end
