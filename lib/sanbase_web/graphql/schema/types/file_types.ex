defmodule SanbaseWeb.Graphql.FileTypes do
  @moduledoc false
  use Absinthe.Schema.Notation

  object :image_data do
    field(:file_name, :string)
    field(:image_url, :string)
    field(:content_hash, :string)
    field(:hash_algorithm, :string)
    field(:error, :string)
  end
end
