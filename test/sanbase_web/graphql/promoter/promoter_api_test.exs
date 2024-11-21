defmodule SanbaseWeb.Graphql.PromoterApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  @moduletag capture_log: true

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(build_conn(), user)
    {:ok, conn: conn, user: user}
  end

  describe "create promoter" do
    test "succeeds when first promoter API returns success", context do
      mutation = create_promoter_query()

      resp_json = promoter_response()
      http_resp = %HTTPoison.Response{body: resp_json, status_code: 200}
      resp = resp_json |> Jason.decode!()

      Sanbase.Mock.prepare_mock2(&HTTPoison.post/3, {:ok, http_resp})
      |> Sanbase.Mock.run_with_mocks(fn ->
        promoter = execute_mutation(context.conn, mutation, "createPromoter")
        promotion = promoter["promotions"] |> hd

        assert promoter["email"] == resp["email"]
        assert promoter["earningsBalance"] == resp["earnings_balance"]["cash"]
        assert promoter["currentBalance"] == resp["current_balance"]["cash"]
        assert promoter["paidBalance"] == resp["paid_balance"]
        assert promotion["visitorsCount"] == resp["promotions"] |> hd |> Map.get("visitors_count")
      end)
    end

    test "errors when API returns error json", context do
      mutation = create_promoter_query()

      error_resp = ~s|{"error":"something wrong"}|
      http_resp = %HTTPoison.Response{body: error_resp, status_code: 404}

      Sanbase.Mock.prepare_mock2(&HTTPoison.post/3, {:ok, http_resp})
      |> Sanbase.Mock.run_with_mocks(fn ->
        error = execute_mutation_with_error(context.conn, mutation)
        assert error == "something wrong"
      end)
    end
  end

  describe "show promoter" do
    test "succeeds when first promoter API returns success", context do
      query = show_promoter_query()

      resp_json = promoter_response()
      http_resp = %HTTPoison.Response{body: resp_json, status_code: 200}
      resp = resp_json |> Jason.decode!()

      Sanbase.Mock.prepare_mock2(&HTTPoison.get/2, {:ok, http_resp})
      |> Sanbase.Mock.run_with_mocks(fn ->
        promoter = execute_query(context.conn, query, "showPromoter")
        promotion = promoter["promotions"] |> hd

        assert promoter["email"] == resp["email"]
        assert promoter["earningsBalance"] == resp["earnings_balance"]["cash"]
        assert promoter["currentBalance"] == resp["current_balance"]["cash"]
        assert promoter["paidBalance"] == resp["paid_balance"]

        assert promoter["dashboardUrl"] ==
                 "https://santiment.firstpromoter.com/view_dashboard_as?at=#{resp["auth_token"]}"

        assert promotion["visitorsCount"] == resp["promotions"] |> hd |> Map.get("visitors_count")
      end)
    end

    test "errors when API returns error json", context do
      query = show_promoter_query()

      error_resp = ~s|{"error":"something wrong"}|
      http_resp = %HTTPoison.Response{body: error_resp, status_code: 404}

      Sanbase.Mock.prepare_mock2(&HTTPoison.get/2, {:ok, http_resp})
      |> Sanbase.Mock.run_with_mocks(fn ->
        error = execute_query_with_error(context.conn, query, "showPromoter")
        assert error == "something wrong"
      end)
    end
  end

  def create_promoter_query() do
    """
    mutation {
      createPromoter(
        refId:"tsetso"
      ) {
        email
        currentBalance
        earningsBalance
        paidBalance
        dashboardUrl
        promotions {
          refId
          referralLink
          promoCode
          visitorsCount
          leadsCount
          salesCount
          customersCount
          refundsCount
          cancellationsCount
          salesTotal
          refundsTotal
        }
      }
    }
    """
  end

  def show_promoter_query() do
    """
     {
      showPromoter {
        email
        currentBalance
        earningsBalance
        paidBalance
        dashboardUrl
        promotions {
          refId
          referralLink
          promoCode
          visitorsCount
          leadsCount
          salesCount
          customersCount
          refundsCount
          cancellationsCount
          salesTotal
          refundsTotal
        }
      }
    }
    """
  end

  def promoter_response() do
    """
    {
      "id": 8798847,
      "cust_id": "165319",
      "email": "test@example.com",
      "temp_password": "YXaRog",
      "default_promotion_id": 10093828,
      "default_ref_id": "test123",
      "earnings_balance": {"cash": 30690},
      "current_balance": {"cash": 30690},
      "paid_balance": null,
      "note": null,
      "created_at": "2024-09-06T08:25:35.353Z",
      "status": "active",
      "pref": "xxxxx",
      "parent_promoter_id": null,
      "w8_form_url": null,
      "w9_form_url": null,
      "auth_token": "test_auth_token",
      "profile": {
        "id": 8845623,
        "first_name": null,
        "last_name": null,
        "website": null,
        "paypal_email": null,
        "avatar_url": null,
        "description": null,
        "company_name": null,
        "address": null,
        "country": null,
        "phone_number": null,
        "vat_id": null,
        "social_accounts": {}
      },
      "promotions": [
        {
          "id": 10093828,
          "status": "offer_inactive",
          "ref_id": "test123",
          "promo_code": null,
          "target_reached_at": null,
          "promoter_id": 8798847,
          "campaign_id": 21911,
          "campaign_name": "Santiment referral program",
          "referral_link": "https://app.santiment.net/?fpr=test123",
          "current_referral_reward": {
            "id": 19088,
            "amount": null,
            "type": "per_referral",
            "unit": "cash",
            "name": "30% recurring commission",
            "default_promo_code": null,
            "per_of_sale": 30
          },
          "current_promotion_reward": null,
          "current_target_reward": null,
          "current_offer": null,
          "customer_promo_code": null,
          "hidden": false,
          "visitors_count": 507,
          "leads_count": 78,
          "customers_count": 5,
          "active_customers_count": 3,
          "refunds_count": 0,
          "cancellations_count": 3,
          "sales_count": 7,
          "sales_total": 102300,
          "refunds_total": 0
        }
      ]
    }
    """
  end
end
