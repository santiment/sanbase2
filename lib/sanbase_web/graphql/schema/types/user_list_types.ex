defmodule SanbaseWeb.Graphql.UserListTypes do
  use Absinthe.Schema.Notation

  import Absinthe.Resolution.Helpers
  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1]

  alias SanbaseWeb.Graphql.SanbaseRepo
  alias SanbaseWeb.Graphql.Resolvers.UserListResolver

  enum(:color_enum, values: [:none, :blue, :red, :green, :yellow, :grey, :black])

  input_object :input_list_item do
    field(:project_id, :integer)
  end

  object :list_item do
    field(:project, :project)
  end

  object :watchlist_stats do
    field(:trending_names, list_of(:string))
    field(:trending_slugs, list_of(:string))
    field(:trending_tickers, list_of(:string))
    field(:trending_projects, list_of(:project))
    field(:projects_count, :integer)
  end

  object :watchlist_settings do
    field(:time_window, :string)
    field(:page_size, :integer)
    field(:table_columns, :json)
  end

  input_object :watchlist_settings_input_object do
    field(:time_window, :string)
    field(:page_size, :integer)
    field(:table_columns, :json)
  end

  object :user_list do
    field(:id, non_null(:id))
    field(:user, non_null(:post_author), resolve: dataloader(SanbaseRepo))
    field(:name, non_null(:string))
    field(:slug, :string)
    field(:description, :string)
    field(:is_public, :boolean)
    field(:color, :color_enum)
    field(:function, :json)
    field(:is_monitored, :boolean)

    field :list_items, list_of(:list_item) do
      resolve(&UserListResolver.list_items/3)
    end

    field(:table_configuration, :table_configuration, resolve: dataloader(SanbaseRepo))

    field(:inserted_at, non_null(:naive_datetime))
    field(:updated_at, non_null(:naive_datetime))

    field(:stats, :watchlist_stats) do
      cache_resolve(&UserListResolver.stats/3)
    end

    field(:historical_stats, list_of(:combined_projects_stats)) do
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "1d")

      cache_resolve(&UserListResolver.historical_stats/3)
    end

    field(:settings, :watchlist_settings) do
      cache_resolve(&UserListResolver.settings/3)
    end
  end
end
