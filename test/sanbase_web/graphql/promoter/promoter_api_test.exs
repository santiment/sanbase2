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
      "id": 2348,
      "cust_id": "cus_sd4gh302fjlsd",
      "email": "jon@doe.com",
      "temp_password": null,
      "default_promotion_id": 3341,
      "default_ref_id": "jon56",
      "earnings_balance": null,
      "current_balance": null,
      "paid_balance": null,
      "note": null,
      "auth_token": "QvpsK_rzpzjYCBxfbATV8ubffmYDUf6u",
      "profile": {
        "id": 3390,
        "first_name": "John",
        "last_name": "Doe",
        "website": "https://google.com",
        "paypal_email": null,
        "avatar_url": null,
        "description": null,
        "social_accounts": {}
      },
      "promotions": [
        {
          "id": 3341,
          "status": "offer_inactive",
          "ref_id": "jon56",
          "promo_code": null,
          "target_reached_at": null,
          "promoter_id": 2348,
          "campaign_id": 1286,
          "referral_link": "http://test.com#_r_jon56",
          "current_referral_reward": {
            "id": 205,
            "amount": 2000,
            "type": "per_referral",
            "unit": "cash",
            "name": "20% recurring commission",
            "default_promo_code": ""
          },
          "current_promotion_reward": null,
          "current_target_reward": null,
          "visitors_count": 1,
          "leads_count": 0,
          "customers_count": 0,
          "refunds_count": 0,
          "cancellations_count": 0,
          "sales_count": 0,
          "sales_total": 0,
          "refunds_total": 0
        }
      ]
    }
    """
  end
end
