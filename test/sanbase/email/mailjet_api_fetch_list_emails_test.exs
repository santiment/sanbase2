defmodule Sanbase.Email.MailjetApiFetchListEmailsTest do
  use ExUnit.Case, async: false

  alias Sanbase.Email.MailjetApi

  @list :api_business_onboarding
  @list_id 12_345
  @stub_name __MODULE__.MailjetStub

  setup do
    previous_client = Application.get_env(:sanbase, :mailjet_api)
    previous_mailjet = Application.get_env(:sanbase, MailjetApi, [])
    previous_mailer = Application.get_env(:sanbase, Sanbase.TemplateMailer, [])

    Application.put_env(:sanbase, :mailjet_api, MailjetApi)

    Application.put_env(
      :sanbase,
      MailjetApi,
      Keyword.merge(previous_mailjet,
        api_business_onboarding_list_id: @list_id,
        fetch_list_page_limit: 2,
        req_options: [plug: {Req.Test, @stub_name}]
      )
    )

    Application.put_env(
      :sanbase,
      Sanbase.TemplateMailer,
      Keyword.merge(previous_mailer, api_key: "test_key", secret: "test_secret")
    )

    on_exit(fn ->
      Application.put_env(:sanbase, :mailjet_api, previous_client)
      Application.put_env(:sanbase, MailjetApi, previous_mailjet)
      Application.put_env(:sanbase, Sanbase.TemplateMailer, previous_mailer)
    end)

    :ok
  end

  test "fetch_list_emails/1 paginates with Limit/Offset until a short page" do
    Req.Test.expect(@stub_name, 3, fn conn ->
      params = URI.decode_query(conn.query_string)
      assert params["ContactsList"] == Integer.to_string(@list_id)
      assert params["Limit"] == "2"

      offset = String.to_integer(params["Offset"])

      data =
        case offset do
          0 -> [%{"Email" => "a@example.com"}, %{"Email" => "b@example.com"}]
          2 -> [%{"Email" => "c@example.com"}, %{"Email" => "d@example.com"}]
          4 -> [%{"Email" => "e@example.com"}]
        end

      Req.Test.json(conn, %{"Data" => data})
    end)

    assert {:ok, emails} = MailjetApi.fetch_list_emails(@list)

    assert emails == [
             "a@example.com",
             "b@example.com",
             "c@example.com",
             "d@example.com",
             "e@example.com"
           ]
  end

  test "fetch_list_emails/1 returns list_not_configured when list id is unset" do
    Application.put_env(
      :sanbase,
      MailjetApi,
      Keyword.put(
        Application.get_env(:sanbase, MailjetApi, []),
        :api_business_onboarding_list_id,
        nil
      )
    )

    assert {:error, :list_not_configured} = MailjetApi.fetch_list_emails(@list)
  end
end
