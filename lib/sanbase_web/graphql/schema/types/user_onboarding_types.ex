defmodule SanbaseWeb.Graphql.UserOnboardingTypes do
  use Absinthe.Schema.Notation

  object :user_onboarding do
    field(:title, :string)
    field(:goal, :string)
    field(:used_tools, list_of(:string))
    field(:uses_behaviour_analysis, :string)
    field(:inserted_at, :datetime)
    field(:updated_at, :datetime)
  end

  input_object :user_onboarding_input_object do
    field(:title, :string)
    field(:goal, :string)
    field(:used_tools, list_of(:string))
    field(:uses_behaviour_analysis, :string)
  end
end
