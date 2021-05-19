defmodule SanbaseWeb.Graphql.Schema.IntercomQueries do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Middlewares.{BasicAuth, JWTAuth}
  alias SanbaseWeb.Graphql.Resolvers.IntercomResolver

  object :user_attribute do
    field(:user_id, :id)
    field(:inserted_at, :datetime)
    field(:properties, :json)
  end

  object :user_event do
    field(:user_id, :id)
    field(:created_at, :datetime)
    field(:event_name, :string)
    field(:metadata, :json)
  end

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
  end

  object :intercom_mutations do
    field :track_events, :boolean do
      arg(:events, :json)

      middleware(JWTAuth)

      resolve(&IntercomResolver.track_events/3)
    end
  end
end
