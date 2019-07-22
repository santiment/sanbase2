import EctoEnum

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
