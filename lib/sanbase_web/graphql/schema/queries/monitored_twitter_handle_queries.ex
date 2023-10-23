defmodule SanbaseWeb.Graphql.Schema.MonitoredTwitterHandleQueries do
  @moduledoc ~s"""
  Queries and mutations for working with short urls
  """
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Middlewares.UserAuth
  alias SanbaseWeb.Graphql.Resolvers.MonitoredTwitterHandleResolver

  object :monitored_twitter_handle_queries do
    field :get_current_user_submitted_twitter_handles, list_of(:monitored_twitter_handle) do
      meta(access: :free)

      middleware(UserAuth)

      resolve(&MonitoredTwitterHandleResolver.get_current_user_submitted_twitter_handles/3)
    end

    field :is_twitter_handle_monitored, :boolean do
      meta(access: :free)

      arg(:twitter_handle, non_null(:string))

      middleware(UserAuth)

      resolve(&MonitoredTwitterHandleResolver.is_twitter_handle_monitored/3)
    end
  end

  object :monitored_twitter_handle_mutations do
    field :add_twitter_handle_to_monitor, :boolean do
      meta(access: :free)

      arg(:twitter_handle, non_null(:string))
      arg(:notes, :string)

      middleware(UserAuth)

      resolve(&MonitoredTwitterHandleResolver.add_twitter_handle_to_monitor/3)
    end
  end
end
