defmodule Sanbase.Insight.PostPaywall do
  @moduledoc """
  Filter paywalled insights for anonymous users or users with free plan that are not insight's author.
  Filtering means removing the text and populating a virtual field that is truncated to
  @words_count_shown_as_preview words of the original text.
  """
  alias Sanbase.Insight.Post
  alias Sanbase.Billing.{Subscription, Product}
  alias Sanbase.Auth.User
  alias Sanbase.Billing.Plan.SanbaseAccessChecker

  # Show only first @words_count_shown_as_preview word of content
  @words_count_shown_as_preview 70
  @product_sanbase Product.product_sanbase()

  def maybe_filter_paywalled(insights, nil), do: maybe_filter(insights, nil)

  def maybe_filter_paywalled(insights, %User{} = user) do
    subscription = Subscription.current_subscription(user, @product_sanbase)

    if SanbaseAccessChecker.access_paywalled_insights?(subscription) do
      insights
    else
      maybe_filter(insights, user.id)
    end
  end

  defp maybe_filter(%Post{} = insight, querying_user_id) do
    do_filter(insight, querying_user_id)
  end

  defp maybe_filter(insights, querying_user_id) when is_list(insights) do
    Enum.map(insights, &do_filter(&1, querying_user_id))
  end

  defp do_filter(%Post{is_paywall_required: false} = insight, _), do: insight

  defp do_filter(%Post{user_id: user_id} = insight, querying_user_id)
       when not is_nil(querying_user_id) and user_id == querying_user_id,
       do: insight

  defp do_filter(%Post{short_desc: short_desc} = insight, _) when is_binary(short_desc) do
    insight
    |> Map.put(:text, nil)
    |> Map.put(:text_preview, short_desc)
  end

  defp do_filter(insight, _) do
    insight
    |> Map.put(:text, nil)
    |> Map.put(:text_preview, text_preview(insight))
  end

  defp text_preview(%Post{text: text}) do
    String.split(text, " ")
    |> Enum.take(@words_count_shown_as_preview)
    |> Enum.join(" ")
  end
end
