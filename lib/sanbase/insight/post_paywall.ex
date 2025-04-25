defmodule Sanbase.Insight.PostPaywall do
  @moduledoc """
  Filter paywalled insights for anonymous users or users with free plan that are not insight's author.
  Filtering means truncating the text to @max_words_shown_as_preview words of the original text.
  """
  alias Sanbase.Insight.Post
  alias Sanbase.Billing.Subscription
  alias Sanbase.Billing.Product
  alias Sanbase.Accounts.User
  alias Sanbase.Billing.Plan.SanbaseAccessChecker

  # Show only first @max_words_shown_as_preview word of content
  @max_words_shown_as_preview 140

  @type insight_or_insights :: %Post{} | [%Post{}]
  @type current_user_or_nil :: %User{} | nil

  @spec maybe_filter_paywalled(insight_or_insights, current_user_or_nil) :: insight_or_insights
  def maybe_filter_paywalled(nil, _), do: nil
  def maybe_filter_paywalled(insights, nil), do: maybe_filter(insights, nil)

  def maybe_filter_paywalled(insights, %User{} = user) do
    subscriptions =
      [
        Subscription.current_subscription(user, Product.product_sanbase()),
        Subscription.current_subscription(user, Product.product_api())
      ]

    can_access? = Enum.any?(subscriptions, &SanbaseAccessChecker.can_access_paywalled_insights?/1)

    if can_access? do
      insights
    else
      maybe_filter(insights, user.id)
    end
  end

  defp maybe_filter(insights, querying_user_id) when is_list(insights) do
    Enum.map(insights, &do_filter(&1, querying_user_id))
  end

  defp do_filter(nil, _), do: nil

  defp do_filter(%Post{is_paywall_required: false} = insight, _), do: insight

  defp do_filter(%Post{user_id: user_id} = insight, user_id), do: insight

  defp do_filter(insight, _) do
    Map.put(insight, :text, truncate(insight))
    |> Map.put(:comments, [])
  end

  defp truncate(%Post{text: text}) do
    Sanbase.HTML.truncate_html(text, @max_words_shown_as_preview)
  end
end
