import EctoEnum

defenum(QuestionType, :question_type, [
  "multiple_select",
  "single_select",
  "open_text",
  "open_number",
  "boolean"
])

defenum(SubscriptionType, :subscription_type, [
  "fiat",
  "liquidity",
  "burning_regular",
  "burning_nft",
  "sanr_points_nft"
])

defenum(WatchlistType, :watchlist_type, ["project", "blockchain_address"])
defenum(TableConfigurationType, :table_configuration_type, ["project", "blockchain_address"])

defenum(ColorEnum, :color, ["none", "blue", "red", "green", "yellow", "grey", "black"])

# https://stripe.com/docs/api/subscriptions/object#subscription_object-status
defenum(SubscriptionStatusEnum, :status, [
  "initial",
  "incomplete",
  "incomplete_expired",
  "trialing",
  "active",
  "past_due",
  "canceled",
  "unpaid"
])

defenum(LangEnum, :lang, ["en", "jp"])
