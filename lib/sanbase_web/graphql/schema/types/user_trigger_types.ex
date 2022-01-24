defmodule SanbaseWeb.Graphql.UserTriggerTypes do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.UserTriggerResolver

  object :user_trigger do
    field(:user_id, :integer)
    field(:trigger, :trigger)
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
    field(:is_active, non_null(:boolean))
    field(:is_repeating, non_null(:boolean))
    field(:is_frozen, non_null(:boolean))
  end
end
