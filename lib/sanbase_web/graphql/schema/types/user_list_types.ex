defmodule SanbaseWeb.Graphql.UserListTypes do
  use Absinthe.Schema.Notation

  import Absinthe.Resolution.Helpers
  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 2]

  alias SanbaseWeb.Graphql.SanbaseRepo
  alias SanbaseWeb.Graphql.Resolvers.{UserListResolver, VoteResolver}

  enum :color_enum do
    value(:none)
    value(:blue)
    value(:red)
    value(:green)
    value(:yellow)
    value(:grey)
    value(:black)
  end

  enum :watchlist_type_enum do
    value(:project)
    value(:blockchain_address)
  end

  input_object :blockchain_address_input_object do
    field(:address, :string)
    field(:infrastructure, :string)
    field(:notes, :string)
    field(:labels, list_of(:string))
  end

  input_object :input_list_item do
    field(:project_id, :integer)
    field(:blockchain_address, :blockchain_address_input_object)
  end

  object :list_item do
    field(:project, :project)
    field(:blockchain_address, :blockchain_address_ephemeral)
  end

  object :watchlist_stats do
    field(:trending_names, list_of(:string))
    field(:trending_slugs, list_of(:string))
    field(:trending_tickers, list_of(:string))
    field(:trending_projects, list_of(:project))
    field(:projects_count, :integer)
    field(:blockchain_addresses_count, :integer)
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
    field(:type, :watchlist_type_enum)

    field :user, non_null(:public_user) do
      resolve(&SanbaseWeb.Graphql.Resolvers.UserResolver.user_no_preloads/3)
    end

    field(:name, non_null(:string))
    field(:slug, :string)
    field(:description, :string)
    field(:is_public, non_null(:boolean))
    field(:is_hidden, non_null(:boolean))
    field(:is_featured, :boolean)
    field(:is_screener, non_null(:boolean))
    field(:color, :color_enum)
    field(:function, :json)
    field(:is_monitored, :boolean)
    field(:views, :integer)

    field :list_items, list_of(:list_item) do
      resolve(&UserListResolver.list_items/3)
    end

    field(:table_configuration, :table_configuration, resolve: dataloader(SanbaseRepo))

    field(:inserted_at, non_null(:naive_datetime))
    field(:updated_at, non_null(:naive_datetime))

    field(:stats, :watchlist_stats) do
      cache_resolve(&UserListResolver.stats/3, honor_do_not_cache_flag: true)
    end

    field(:historical_stats, list_of(:combined_projects_stats)) do
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "1d")

      cache_resolve(&UserListResolver.historical_stats/3, honor_do_not_cache_flag: true)
    end

    field(:settings, :watchlist_settings) do
      cache_resolve(&UserListResolver.settings/3, honor_do_not_cache_flag: true)
    end

    field :comments_count, :integer do
      resolve(&UserListResolver.comments_count/3)
    end

    field :voted_at, :datetime do
      resolve(&VoteResolver.voted_at/3)
    end

    field :votes, :vote do
      resolve(&VoteResolver.votes/3)
    end
  end
end
