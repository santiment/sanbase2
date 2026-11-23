defmodule Sanbase.Intercom do
  @moduledoc """
  Intercom API client: creates contacts for newly registered users, updates
  contact attributes and fetches user events.
  """

  import Ecto.Query
  import Sanbase.Accounts.User.Ecto, only: [is_registered: 0]

  alias Sanbase.Utils.Config
  alias Sanbase.Accounts.{User, ProtectedUser, ActivityTracesConfig}
  alias Sanbase.Repo

  require Logger

  @user_events_url "https://api.intercom.io/events?type=user"
  @contacts_url "https://api.intercom.io/contacts"
  @data_attributes_url "https://api.intercom.io/data_attributes"

  def sync_newly_registered_to_intercom() do
    since = Timex.shift(Timex.now(), hours: -30)

    if has_intercom_api_key?() do
      sync_newly_registered_to_intercom(since)
    end

    :ok
  end

  def sync_newly_registered_to_intercom(dt) do
    hidden_ids = intercom_hidden_ids()

    fetch_new_registrations_since(dt)
    # NDA-protected users must not be created as contacts in the external CRM.
    |> Enum.reject(&MapSet.member?(hidden_ids, &1))
    |> Enum.each(fn user_id ->
      if is_nil(get_contact_by_user_id(user_id)) do
        create_contact(user_id)
      end
    end)
  end

  # Protected-user id set to exclude from the CRM export, or an empty set
  # when the `hide_intercom` switch is off (then the rejects are no-ops).
  defp intercom_hidden_ids() do
    if ActivityTracesConfig.enabled?(:hide_intercom) do
      ProtectedUser.activity_traces_hidden_user_ids()
    else
      MapSet.new()
    end
  end

  def save_contacts_to_intercom(contacts) do
    contacts
    |> Enum.each(fn contact ->
      update_contact(contact["id"], contact)
    end)
  end

  def fetch_new_registrations_since(dt) do
    from(u in User, where: is_registered() and u.inserted_at > ^dt, select: u.id)
    |> Repo.all()
  end

  def create_contact(user_id) do
    body =
      %{
        role: "user",
        external_id: user_id
      }
      |> Jason.encode!()

    HTTPoison.post(@contacts_url, body, intercom_headers())
  end

  def create_data_attribute(name, type) do
    body =
      %{
        name: name,
        model: "contact",
        data_type: type
      }
      |> Jason.encode!()

    HTTPoison.post(@data_attributes_url, body, intercom_headers())
  end

  def list_data_attributes() do
    HTTPoison.get(@data_attributes_url <> "?model=contact", intercom_headers())
  end

  def get_contact_by_user_id(user_id) do
    body =
      %{
        query: %{
          field: "external_id",
          operator: "=",
          value: user_id |> to_string()
        }
      }
      |> Jason.encode!()

    with {:ok, response} <- HTTPoison.post("#{@contacts_url}/search", body, intercom_headers()) do
      response
      |> Map.get(:body)
      |> Jason.decode!()
      |> Map.get("data")
      |> List.first()
    end
  end

  def update_contact(intercom_id, params) do
    body_json = Jason.encode!(params)

    HTTPoison.put("#{@contacts_url}/#{intercom_id}", body_json, intercom_headers())
    |> case do
      {:ok, response} ->
        response

      {:error, reason} ->
        Logger.error("Error updating contact: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def get_events_for_user(user_id, since \\ nil) do
    url = "#{@user_events_url}&user_id=#{user_id}"
    url = if since, do: "#{url}&since=#{since}", else: url

    fetch_all_events(url)
  end

  def has_intercom_api_key?() do
    apikey = intercom_api_key()
    is_binary(apikey) and apikey != ""
  end

  defp fetch_all_events(url, all_events \\ []) do
    case fetch_events(url) do
      {:ok, %{"events" => []}} ->
        all_events

      {:ok, %{"events" => events, "pages" => %{"next" => next}}} ->
        fetch_all_events(next, all_events ++ events)

      {:ok, %{"events" => events}} ->
        all_events ++ events

      {:error, _} ->
        all_events
    end
  end

  defp fetch_events(url) do
    HTTPoison.get(url, intercom_headers())
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        Jason.decode(body)

      {:ok, %HTTPoison.Response{} = response} ->
        Logger.error(
          "Error fetching intercom events for url: #{url}. Response: #{inspect(response)}"
        )

        {:error, response}

      {:error, reason} ->
        Logger.error("Error fetching intercom events for url: #{url}. Reason: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp intercom_headers() do
    [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"},
      {"Authorization", "Bearer #{intercom_api_key()}"},
      {"Intercom-Version", "2.5"}
    ]
  end

  defp intercom_api_key() do
    Config.module_get(__MODULE__, :api_key)
  end
end
