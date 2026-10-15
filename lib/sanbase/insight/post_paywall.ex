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
  @type auth_or_nil :: %{current_user: %User{}} | nil

  @doc ~s"""
  Truncate the paywalled insights the user cannot access.

  Takes the request's auth map, not just the user, so the subscriptions that
  `SanbaseWeb.Graphql.AuthPlug` already loaded are reused instead of queried.

  ## Options
    - exempt_author: whether the author sees their own paywalled insights in full.
      Defaults to true.
  """
  @spec maybe_filter_paywalled(insight_or_insights, auth_or_nil, Keyword.t()) ::
          insight_or_insights
  def maybe_filter_paywalled(insights, auth, opts \\ [])
  def maybe_filter_paywalled(nil, _, _opts), do: nil

  def maybe_filter_paywalled(insights, auth, opts) do
    insights
    |> filter_paywalled_with_access(auth, opts)
    |> Enum.map(fn {insight, _full_access?} -> insight end)
  end

  @doc ~s"""
  Like `maybe_filter_paywalled/3`, but pairs each insight with whether the user
  gets it in full. Use it when the access result is needed, as a truncated text
  can be equal to the full text of a short insight.
  """
  @spec filter_paywalled_with_access([%Post{}], auth_or_nil, Keyword.t()) ::
          [{%Post{} | nil, boolean()}]
  def filter_paywalled_with_access(insights, auth, opts \\ []) when is_list(insights) do
    exempt_user_id = exempt_user_id(auth, opts)

    Enum.map(insights, fn insight ->
      if full_access?(insight, exempt_user_id),
        do: {insight, true},
        else: {do_filter(insight), false}
    end)
  end

  # Returns :all when the user's plan can access every paywalled insight.
  defp exempt_user_id(%{current_user: %User{} = user} = auth, opts) do
    subscriptions =
      [
        Subscription.current_subscription_from_auth(auth, Product.product_sanbase()),
        Subscription.current_subscription_from_auth(auth, Product.product_api())
      ]

    can_access? = Enum.any?(subscriptions, &SanbaseAccessChecker.can_access_paywalled_insights?/1)

    cond do
      can_access? -> :all
      Keyword.get(opts, :exempt_author, true) -> user.id
      true -> nil
    end
  end

  defp exempt_user_id(_no_user, _opts), do: nil

  defp full_access?(nil, _), do: true
  defp full_access?(_insight, :all), do: true
  defp full_access?(%Post{is_paywall_required: false}, _), do: true
  defp full_access?(%Post{user_id: user_id}, user_id) when not is_nil(user_id), do: true
  defp full_access?(_insight, _), do: false

  defp do_filter(insight) do
    Map.put(insight, :text, truncate(insight))
    |> Map.put(:comments, [])
  end

  defp truncate(%Post{text: text}) do
    Sanbase.HTML.truncate_html(text, @max_words_shown_as_preview)
  end
end
