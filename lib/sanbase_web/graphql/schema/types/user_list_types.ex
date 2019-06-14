defmodule SanbaseWeb.Graphql.UserListTypes do
  use Absinthe.Schema.Notation

  import Absinthe.Resolution.Helpers

  alias SanbaseWeb.Graphql.SanbaseRepo
  alias SanbaseWeb.Graphql.Resolvers.UserListResolver

  enum(:color_enum, values: [:none, :blue, :red, :green, :yellow, :grey, :black])

  input_object :input_list_item do
    field(:project_id, :integer)
  end

  object :list_item do
    field(:project, :project)
  end

  object :user_list do
    field(:id, non_null(:id))
    field(:user, non_null(:post_author), resolve: dataloader(SanbaseRepo))
    field(:name, non_null(:string))
    field(:is_public, :boolean)
    field(:color, :color_enum)
    field(:function, :json)
    field(:list_items, list_of(:list_item), resolve: &UserListResolver.list_items/3)
    field(:inserted_at, non_null(:naive_datetime))
    field(:updated_at, non_null(:naive_datetime))
  end
end
