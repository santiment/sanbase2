defmodule SanbaseWeb.Graphql.UserTriggerTypes do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1, cache_resolve: 2]

  alias SanbaseWeb.Graphql.Resolvers.UserTriggerResolver
  alias SanbaseWeb.Graphql.Resolvers.VoteResolver

  object :user_trigger do
    field(:user_id, :integer, deprecate: "Use userPublicId or the nested user { publicId }")

    field :user_public_id, :string do
      resolve(fn parent, _, _ ->
        case Sanbase.Accounts.User.by_id(parent.user_id) do
          {:ok, user} -> {:ok, user.public_id}
          _ -> {:ok, nil}
        end
      end)
    end

    field :user, :public_user do
      cache_resolve(&SanbaseWeb.Graphql.Resolvers.UserResolver.user_no_preloads/3,
        ttl: 60,
        max_ttl: 60
      )
    end

    field(:trigger, :trigger)

    field :voted_at, :datetime do
      resolve(&VoteResolver.voted_at/3)
    end

    field :votes, :vote do
      resolve(&VoteResolver.votes/3)
    end

    field(:views, :integer)
  end

  object :trigger do
    field(:id, non_null(:integer))
    field(:title, non_null(:string))
    field(:description, :string)
    field(:icon_url, :string)
    field(:tags, list_of(:tag))

    field :last_triggered_datetime, :datetime do
      resolve(&UserTriggerResolver.last_triggered_datetime/3)
    end

    field(:settings, non_null(:json))
    field(:cooldown, non_null(:string))
    field(:is_public, non_null(:boolean))
    field(:is_hidden, non_null(:boolean))
    field(:is_active, non_null(:boolean))
    field(:is_repeating, non_null(:boolean))
    field(:is_frozen, non_null(:boolean))
    field(:is_featured, :boolean)

    field(:inserted_at, :datetime)
    field(:updated_at, :datetime)
  end

  object :public_user_trigger do
    field(:user_id, :integer, deprecate: "Use userPublicId or the nested user { publicId }")

    field :user_public_id, :string do
      resolve(fn parent, _, _ ->
        case Sanbase.Accounts.User.by_id(parent.user_id) do
          {:ok, user} -> {:ok, user.public_id}
          _ -> {:ok, nil}
        end
      end)
    end

    field :user, :public_user do
      cache_resolve(&SanbaseWeb.Graphql.Resolvers.UserResolver.user_no_preloads/3,
        ttl: 60,
        max_ttl: 60
      )
    end

    field(:trigger, :public_trigger)

    field :voted_at, :datetime do
      resolve(&VoteResolver.voted_at/3)
    end

    field :votes, :vote do
      resolve(&VoteResolver.votes/3)
    end

    field(:views, :integer)
  end

  @desc ~s"""
  A public-safe representation of a trigger. Same shape as :trigger but
  with private fields removed: no cooldown, is_hidden. The settings JSON
  has private keys (channel, template, extra_explanation) stripped out.
  """
  object :public_trigger do
    field(:id, non_null(:integer))
    field(:title, non_null(:string))
    field(:description, :string)
    field(:icon_url, :string)
    field(:tags, list_of(:tag))

    field :last_triggered_datetime, :datetime do
      resolve(&UserTriggerResolver.last_triggered_datetime/3)
    end

    field(:settings, non_null(:json))
    field(:is_public, non_null(:boolean))
    field(:is_active, non_null(:boolean))
    field(:is_repeating, non_null(:boolean))
    field(:is_frozen, non_null(:boolean))
    field(:is_featured, :boolean)
    field(:inserted_at, :datetime)
    field(:updated_at, :datetime)
  end

  object :alerts_stats do
    field(:total_fired, :integer)
    field(:total_fired_weekly_avg, :float)
    field(:total_fired_percent_change, :float)
    field(:data, list_of(:alert_stats))
  end

  object :alert_stats do
    field(:slug, :string)

    field :project, :project do
      cache_resolve(&UserTriggerResolver.project/3)
    end

    field(:count, :integer)
    field(:percent_change, :float)
    field(:alert_types, list_of(:string))
  end
end
