defmodule SanbaseWeb.Graphql.Schema.IntercomQueries do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Middlewares.{BasicAuth, SanbaseProductOrigin}
  alias SanbaseWeb.Graphql.Resolvers.IntercomResolver

  object :intercom_queries do
    @desc ~s"""
    Get user attributes over time.
    Args:
    * `users`: List of integer user ids
    * `days`: Historical days, default: 30

    or alternatively:
    * from: start datetime, default: `days` arg
    * to: end datetime, default: now
    """
    field :get_attributes_for_users, list_of(:user_attribute) do
      meta(access: :free)

      arg(:users, non_null(list_of(:id)))
      arg(:days, non_null(:integer), default_value: 30)
      arg(:from, :datetime)
      arg(:to, :datetime)

      middleware(BasicAuth)

      resolve(&IntercomResolver.get_attributes_for_users/3)
    end

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
      arg(:events, non_null(:json))

      # Do not allow this mutation to be called from scritps, sanpy, etc.
      # Allow only requests coming from Sanbase. It allows both
      # authenticated and non-authenticated requests.
      middleware(SanbaseProductOrigin)

      resolve(&IntercomResolver.track_events/3)
    end
  end
end
