defmodule SanbaseWeb.Graphql.UserTriggerTypes do
  use Absinthe.Schema.Notation

  object :user_trigger do
    field(:user_id, :integer)
    field(:trigger, :trigger)
  end

  object :trigger do
    field(:id, :string)
    field(:settings, :json)
    field(:is_public, :boolean)
    field(:cooldown, :integer)
  end
end
