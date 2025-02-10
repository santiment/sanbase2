defmodule SanbaseWeb.Graphql.Resolvers.PromoterResolver do
  @moduledoc false
  alias Sanbase.Affiliate.FirstPromoter

  def create_promoter(_root, args, %{context: %{auth: %{current_user: current_user}}}) do
    current_user
    |> FirstPromoter.create_promoter(args)
    |> extract_and_atomize_needed_fields()
  end

  def show_promoter(_root, _args, %{context: %{auth: %{current_user: current_user}}}) do
    current_user
    |> FirstPromoter.show_promoter()
    |> extract_and_atomize_needed_fields()
  end

  defp extract_and_atomize_needed_fields({:error, _} = result), do: result

  # Note: Adding new field to extract should be also reflected by adding it in promoter_types.ex
  defp extract_and_atomize_needed_fields({:ok, promoter}) do
    auth_token = promoter["auth_token"]

    promoter =
      promoter
      |> Map.take([
        "email",
        "earnings_balance",
        "current_balance",
        "paid_balance",
        "promotions"
      ])
      |> Map.update("earnings_balance", nil, fn
        %{"cash" => value} -> value
        other -> other
      end)
      |> Map.update("current_balance", nil, fn
        %{"cash" => value} -> value
        other -> other
      end)
      |> Map.update("paid_balance", nil, fn
        %{"cash" => value} -> value
        other -> other
      end)
      |> Map.update("promotions", [], fn promotions ->
        Enum.map(promotions, fn promotion ->
          Map.take(promotion, [
            "ref_id",
            "referral_link",
            "promo_code",
            "visitors_count",
            "leads_count",
            "customers_count",
            "cancellations_count",
            "sales_count",
            "sales_total",
            "refunds_count",
            "refunds_total"
          ])
        end)
      end)
      |> Sanbase.MapUtils.atomize_keys()

    promoter = Map.put(promoter, :dashboard_url, "https://santiment.firstpromoter.com/view_dashboard_as?at=#{auth_token}")

    {:ok, promoter}
  end
end
