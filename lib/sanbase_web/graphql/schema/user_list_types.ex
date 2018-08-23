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
    field :project, :project do
      resolve(&UserListResolver.project_by_list_item/3)
    end
  end

  object :user_list do
    field(:id, non_null(:id))
    field(:user, non_null(:post_author), resolve: dataloader(SanbaseRepo))
    field(:name, :string)
    field(:is_public, :boolean)
    field(:color, :color_enum)
    field(:list_items, list_of(:list_item))
    field(:inserted_at, non_null(:naive_datetime))
    field(:updated_at, non_null(:naive_datetime))
  end
end
