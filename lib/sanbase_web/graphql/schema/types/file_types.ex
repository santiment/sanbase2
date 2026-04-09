defmodule SanbaseWeb.Graphql.FileTypes do
  use Absinthe.Schema.Notation

  object :image_data do
    field(:file_name, :string)
    field(:image_url, :string)
    field(:image_url_w400, :string)
    field(:image_url_w800, :string)
    field(:image_url_w1200, :string)
    field(:image_url_w2000, :string)
    field(:content_hash, :string)
    field(:hash_algorithm, :string)
    field(:error, :string)
  end
end
