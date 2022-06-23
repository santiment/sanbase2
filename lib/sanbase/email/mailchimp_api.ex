defmodule Sanbase.Email.MailchimpApi do
  require Sanbase.Utils.Config, as: Config
  require Logger

  @base_url "https://us14.api.mailchimp.com/3.0"
  @weekly_digest_list_id "41325871aa"
  @bi_weekly_list_id "3e5b56534c"
  @monthly_newsletter_list_id "e3bb1f6827"

  @mailchimp_lists %{
    bi_weekly: @bi_weekly_list_id,
    monthly_newsletter: @monthly_newsletter_list_id
  }

  def account() do
    Mailchimp.Account.get!()
  end

  def all_lists do
    Mailchimp.Account.get_all_lists!() |> Enum.map(&Map.take(&1, [:id, :name]))
  end

  def list(account, list_id) do
    Mailchimp.Account.get_list!(account, list_id)
  end

  def members(list) do
    members(list, [], 0)
  end

  defp members(list, members, offset) do
    new_members =
      Mailchimp.List.members!(list, %{
        fields: "members.email_address,members.status",
        count: 1000,
        offset: offset
      })
      |> Enum.map(&Map.take(&1, [:email_address, :status]))

    case length(new_members) < 1000 do
      true -> members ++ new_members
      false -> members(list, members ++ new_members, offset + length(new_members))
    end
  end

  def subscribe(list_atom, email_or_emails) do
    account()
    |> list(@mailchimp_lists[list_atom])
    |> batch_subscribe(List.wrap(email_or_emails))
  end

  def unsubscribe(list_atom, email_or_emails) do
    account()
    |> list(@mailchimp_lists[list_atom])
    |> batch_unsubscribe(List.wrap(email_or_emails))
  end

  def batch_subscribe(list, emails) when is_list(emails) do
    members = emails |> Enum.map(fn email -> %{email_address: email, status: "subscribed"} end)
    Mailchimp.List.batch_subscribe!(list, members, %{update_existing: true})
  end

  def batch_unsubscribe(list, emails) when is_list(emails) do
    members = emails |> Enum.map(fn email -> %{email_address: email, status: "unsubscribed"} end)
    Mailchimp.List.batch_subscribe!(list, members, %{update_existing: true})
  end

  def add_email_to_mailchimp(email) do
    %{
      email_address: email,
      status: "subscribed"
    }
    |> Jason.encode!()
    |> subscribe_to_digest()
  end

  def subscribe_email(email) do
    body_json =
      %{
        email_address: email,
        status: "subscribed"
      }
      |> Jason.encode!()

    do_subscribe_unsubscribe(email, body_json, "subscribe")
  end

  def unsubscribe_email(email) do
    body_json =
      %{
        email_address: email,
        status: "unsubscribed"
      }
      |> Jason.encode!()

    do_subscribe_unsubscribe(email, body_json, "unsubscribe")
  end

  def do_subscribe_unsubscribe(email, body_json, type) do
    if mailchimp_api_key() do
      subscriber_hash = :crypto.hash(:md5, String.downcase(email)) |> Base.encode16(case: :lower)

      HTTPoison.patch(
        "#{@base_url}/lists/#{@weekly_digest_list_id}/members/#{subscriber_hash}",
        body_json,
        headers()
      )
      |> case do
        {:ok, %HTTPoison.Response{status_code: 200}} ->
          Logger.info("Email #{type} from Mailchimp: #{body_json}")
          :ok

        {:ok, %HTTPoison.Response{} = response} ->
          Logger.error(
            "Error #{type} email from Mailchimp: #{inspect(body_json)}}. Response: #{inspect(response)}"
          )

        {:error, reason} ->
          Logger.error(
            "Error #{type} email from Mailchimp : #{body_json}}. Reason: #{inspect(reason)}"
          )
      end
    else
      :ok
    end
  end

  def subscribe_to_digest(body_json) do
    HTTPoison.post(weekly_digest_members_url(), body_json, headers())
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200}} ->
        Logger.info("Email added to Mailchimp: #{body_json}")
        :ok

      {:ok, %HTTPoison.Response{} = response} ->
        Logger.error(
          "Error adding email to Mailchimp: #{inspect(body_json)}}. Response: #{inspect(response)}"
        )

        {:error, response.body}

      {:error, reason} ->
        Logger.error(
          "Error adding email to Mailchimp : #{body_json}}. Reason: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp mailchimp_api_key() do
    Config.get(:api_key)
  end

  defp weekly_digest_members_url do
    "#{@base_url}/lists/#{@weekly_digest_list_id}/members"
  end

  defp headers do
    [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"},
      {"Authorization", "apikey #{mailchimp_api_key()}"}
    ]
  end
end
