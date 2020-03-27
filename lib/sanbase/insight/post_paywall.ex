defmodule Sanbase.Insight.PostPaywall do
  @moduledoc """
  Filter paywalled insights for anonymous users or users with free plan that are not insight's author.
  Filtering means truncating the text to @max_words_shown_as_preview words of the original text.
  """
  alias Sanbase.Insight.Post
  alias Sanbase.Billing.{Subscription, Product}
  alias Sanbase.Auth.User
  alias Sanbase.Billing.Plan.SanbaseAccessChecker

  # Show only first @max_words_shown_as_preview word of content
  @max_words_shown_as_preview 140
  @product_sanbase Product.product_sanbase()

  @type current_user_or_nil :: %User{} | nil

  @spec maybe_filter_paywalled_insights([%Post{}], current_user_or_nil) :: [%Post{}]
  def maybe_filter_paywalled_insights(insights, nil),
    do: Enum.map(insights, &maybe_filter_insight(&1, nil))

  def maybe_filter_paywalled_insights(insights, %User{} = user) do
    subscription = Subscription.current_subscription(user, @product_sanbase)

    if SanbaseAccessChecker.can_access_paywalled_insights?(subscription) do
      insights
    else
      Enum.map(insights, &maybe_filter_insight(&1, user.id))
    end
  end

  defp maybe_filter_insight(%Post{is_paywall_required: false} = insight, _), do: insight

  defp maybe_filter_insight(%Post{user_id: user_id} = insight, querying_user_id)
       when not is_nil(querying_user_id) and user_id == querying_user_id,
       do: insight

  defp maybe_filter_insight(%Post{short_desc: short_desc} = insight, _)
       when is_binary(short_desc) do
    Map.put(insight, :text, short_desc)
  end

  defp maybe_filter_insight(insight, _) do
    Map.put(insight, :text, truncate(insight))
    |> Map.put(:comments, [])
  end

  defp truncate(%Post{text: text}) do
    Sanbase.HTML.truncate_html(text, @max_words_shown_as_preview)
  end
end
