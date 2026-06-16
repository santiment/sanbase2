defmodule Sanbase.Billing.PaymentError do
  @moduledoc """
  Translates a Stripe PaymentIntent `last_payment_error` into values that are
  safe to expose to end users.

  Stripe's raw `code`/`decline_code`/`message` are not all safe to surface:

    * fraud/security-sensitive decline codes (e.g. `lost_card`, `stolen_card`,
      `fraudulent`, `merchant_blacklist`) must not be revealed to the cardholder
      — doing so would tip off someone misusing a flagged/lost/stolen card, and
    * non-`card_error` failures carry integration/technical messages not meant
      for end users.

  `safe_code/1` collapses those cases into `"generic_decline"`; `user_message/1`
  returns curated, user-facing copy with a generic fallback. The frontend should
  render `user_message` and branch behaviour on `safe_code`, never the raw
  fields.
  """

  # Decline codes we never surface raw to the cardholder: revealing them would
  # tip off someone misusing a flagged/lost/stolen card, and Stripe likewise
  # recommends showing only a generic message for these. They collapse to
  # "generic_decline".
  @sensitive_decline_codes ~w(
    lost_card stolen_card fraudulent pickup_card
    merchant_blacklist security_violation restricted_card
    revocation_of_authorization revocation_of_all_authorizations stop_payment_order
  )

  # Codes where retrying the *same* card is futile — the user must re-enter or
  # switch cards. Everything else defaults to a "retry" action.
  @use_different_card_codes ~w(
    expired_card incorrect_cvc incorrect_number card_not_supported
    currency_not_supported
  )

  @limit_reached_message "Your card's limit has been reached. Retry later, or use a different card."

  # Curated, actionable copy per (non-sensitive) decline code. Note we never tell
  # the user they were charged — the FE renders a fixed "You haven't been
  # charged" line on any failed state, so it isn't duplicated here.
  @messages %{
    "insufficient_funds" =>
      "Your bank declined the payment (insufficient funds). This can be temporary — try again. If it keeps failing, check your balance or use a different card.",
    "expired_card" => "Your card has expired. Please use a different card.",
    "incorrect_cvc" =>
      "Your card's security code (CVC) is incorrect. Re-enter your card details and try again.",
    "incorrect_number" =>
      "Your card number is incorrect. Re-enter your card details and try again.",
    "card_velocity_exceeded" => @limit_reached_message,
    "withdrawal_count_limit_exceeded" => @limit_reached_message,
    "card_not_supported" =>
      "Your card isn't supported for this purchase. Please use a different card.",
    "currency_not_supported" =>
      "Your card doesn't support this currency. Please use a different card.",
    "processing_error" =>
      "Something went wrong while processing your card. Please try again in a few moments.",
    "do_not_honor" =>
      "Your bank declined the payment. Contact your bank to authorize it, or use a different card.",
    "transaction_not_allowed" =>
      "Your bank doesn't allow this type of payment. Contact your bank, or use a different card."
  }

  @generic_message "Your payment couldn't be completed. Please try again or use a different card — and contact your bank if it keeps happening."

  @doc """
  Builds the frontend-safe payload for a Stripe `last_payment_error`, computed
  once: `%{safe_code, user_message, recommended_action}`, or nil when there's no
  error. This is what the GraphQL `:payment_error` object resolves from.
  """
  @spec to_safe_map(map() | struct() | nil) :: map() | nil
  def to_safe_map(nil), do: nil

  def to_safe_map(error) do
    %{
      safe_code: safe_code(error),
      user_message: user_message(error),
      recommended_action: recommended_action(error)
    }
  end

  @doc "Returns a frontend-safe code for branching, or nil when there's no error."
  @spec safe_code(map() | struct() | nil) :: String.t() | nil
  def safe_code(nil), do: nil

  def safe_code(error) do
    decline_code = get(error, :decline_code)
    code = get(error, :code)

    cond do
      get(error, :type) != "card_error" -> "generic_decline"
      decline_code in @sensitive_decline_codes -> "generic_decline"
      code in @sensitive_decline_codes -> "generic_decline"
      is_binary(decline_code) -> decline_code
      is_binary(code) -> code
      true -> "generic_decline"
    end
  end

  @doc "Returns user-facing copy for the error, or nil when there's no error."
  @spec user_message(map() | struct() | nil) :: String.t() | nil
  def user_message(nil), do: nil

  def user_message(error) do
    case safe_code(error) do
      nil -> nil
      code -> Map.get(@messages, code, @generic_message)
    end
  end

  @doc """
  Primary action the frontend should offer: `"use_different_card"` when retrying
  the same card is futile, otherwise `"retry"`. The FE should still expose the
  other action as a secondary option. Nil when there's no error.

  When Stripe's network `advice_code` is present on `last_payment_error` (it is
  only emitted on recent Stripe API versions), it's the most authoritative
  signal and takes precedence; otherwise we fall back to the decline code.
  """
  @spec recommended_action(map() | struct() | nil) :: String.t() | nil
  def recommended_action(nil), do: nil

  def recommended_action(error) do
    case get(error, :advice_code) do
      "try_again_later" -> "retry"
      "do_not_try_again" -> "use_different_card"
      "confirm_card_data" -> "use_different_card"
      _ -> decline_code_action(error)
    end
  end

  defp decline_code_action(error) do
    if safe_code(error) in @use_different_card_codes, do: "use_different_card", else: "retry"
  end

  # Stripe's converter may hand us a struct or a map with atom or string keys.
  defp get(error, key) when is_map(error) do
    Map.get(error, key) || Map.get(error, to_string(key))
  end

  defp get(_, _), do: nil
end
