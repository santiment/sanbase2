defmodule SanbaseWeb.Graphql.UserTriggerTypes do
  use Absinthe.Schema.Notation

  object :user_trigger do
    field(:id, :string)
    field(:trigger, :json)
    field(:is_public, :boolean)
    field(:cooldown, :integer)
  end
end
