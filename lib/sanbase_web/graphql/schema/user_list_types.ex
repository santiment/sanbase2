defmodule SanbaseWeb.Graphql.UserListTypes do
  use Absinthe.Schema.Notation

  import Absinthe.Resolution.Helpers
  alias SanbaseWeb.Graphql.SanbaseRepo

  enum(:color_enum, values: [:none, :blue, :red, :green, :yellow, :grey, :black])

  object :list_item do
    field(:project, :project, resolve: dataloader(SanbaseRepo))
  end

  object :user_list do
    field(:id, non_null(:id))
    field(:user, non_null(:post_author), resolve: dataloader(SanbaseRepo))
    field(:name, :string)
    field(:is_public, :boolean)
    field(:color, :color_enum)
    field(:list_items, list_of(:list_item))
  end
end
