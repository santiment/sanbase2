defmodule SanbaseWeb.Graphql.Schema.IntercomQueries do
  @moduledoc false
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Middlewares.BasicAuth
  alias SanbaseWeb.Graphql.Middlewares.SanbaseProductOrigin
  alias SanbaseWeb.Graphql.Resolvers.IntercomResolver

  object :intercom_queries do
    field :get_events_for_users, list_of(:user_event) do
      meta(access: :free)

      arg(:users, non_null(list_of(:id)))
      arg(:days, non_null(:integer), default_value: 30)
      arg(:from, :datetime)
      arg(:to, :datetime)

      middleware(BasicAuth)

      resolve(&IntercomResolver.get_events_for_users/3)
    end

    field :api_metric_distribution, list_of(:metrics_count) do
      meta(access: :free)
      middleware(BasicAuth)

      resolve(&IntercomResolver.api_metric_distribution/3)
    end

    field :api_metric_distribution_per_user, list_of(:api_metric_distribution_per_user) do
      meta(access: :free)
      middleware(BasicAuth)

      resolve(&IntercomResolver.api_metric_distribution_per_user/3)
    end
  end

  object :intercom_mutations do
    field :track_events, :boolean do
      arg(:anonymous_user_id, :string)
      arg(:events, :json)

      # Do not allow this mutation to be called from scritps, sanpy, etc.
      # Allow only requests coming from Sanbase. It allows both
      # authenticated and non-authenticated requests.
      middleware(SanbaseProductOrigin)

      resolve(&IntercomResolver.track_events/3)
    end
  end
end
