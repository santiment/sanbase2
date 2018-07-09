defmodule SanbaseWeb.Graphql.UserListTypes do
  use Absinthe.Schema.Notation

  import Absinthe.Resolution.Helpers
  alias SanbaseWeb.Graphql.SanbaseRepo

  # enum :color_enum, values: [:none, :blue, :red, :green, :yellow, :grey, :black]

  object :list_item do
    field(:project, :project)
  end

  object :user_list do
    field(:id, non_null(:id))
    field(:user, non_null(:post_author), resolve: dataloader(SanbaseRepo))
    field(:name, :string)
    field(:is_public, :boolean)
    field(:color, :string)
    field(:list_items, list_of(:list_item), resolve: dataloader(SanbaseRepo))
    # field :created_at, non_null(:datetime) do
    #   resolve(fn %{inserted_at: inserted_at}, _, _ ->
    #     {:ok, NaiveDateTime.to_iso8601(inserted_at)}
    #   end)
    # end
    # field(:inserted_at, non_null(:datetime))
    # field(:updated_at, non_null(:datetime))
  end
end
