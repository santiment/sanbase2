defmodule SanbaseWeb.Graphql.UserOnboardingTypes do
  use Absinthe.Schema.Notation

  enum :user_onboarding_title do
    value(:crypto_trader, as: "crypto_trader")
    value(:researcher, as: "researcher")
    value(:content_maker, as: "content_maker")
    value(:new_in_crypto, as: "new_in_crypto")
  end

  enum :user_onboarding_goal do
    value(:catch_trends, as: "catch_trends")
    value(:make_better_trade_entries, as: "make_better_trade_entries")
    value(:build_analysis, as: "build_analysis")
    value(:understand_whats_going_on, as: "understand_whats_going_on")
  end

  enum :user_onboarding_used_tool do
    value(:price_charts, as: "price_charts")
    value(:screeners, as: "screeners")
    value(:on_chain_analytics, as: "on_chain_analytics")
    value(:social_signals, as: "social_signals")
    value(:news_feeds, as: "news_feeds")
    value(:none_of_the_above, as: "none_of_the_above")
  end

  enum :user_onboarding_behaviour_analysis_answer do
    value(:yes, as: "yes")
    value(:no, as: "no")
    value(:not_sure, as: "not_sure")
  end

  object :user_onboarding do
    field(:title, :user_onboarding_title)
    field(:goal, :user_onboarding_goal)
    field(:used_tools, list_of(:user_onboarding_used_tool))
    field(:uses_behaviour_analysis, :user_onboarding_behaviour_analysis_answer)
    field(:inserted_at, :datetime)
    field(:updated_at, :datetime)
  end

  input_object :user_onboarding_input_object do
    field(:title, :user_onboarding_title)
    field(:goal, :user_onboarding_goal)
    field(:used_tools, list_of(:user_onboarding_used_tool))
    field(:uses_behaviour_analysis, :user_onboarding_behaviour_analysis_answer)
  end
end
