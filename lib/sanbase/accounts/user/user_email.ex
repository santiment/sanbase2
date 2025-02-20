defmodule Sanbase.Accounts.User.Email do
  alias Sanbase.Repo
  alias Sanbase.Accounts.User

  import Sanbase.Accounts.EventEmitter, only: [emit_event: 3]

  require Mockery.Macro

  @token_valid_window_minutes 60
  @email_token_length 64

  def generate_email_token() do
    :crypto.strong_rand_bytes(@email_token_length) |> Base.url_encode64()
  end

  def find_by_email_candidate(email_candidate, email_candidate_token) do
    email_candidate = String.downcase(email_candidate)

    case Repo.get_by(User,
           email_candidate: email_candidate,
           email_candidate_token: email_candidate_token
         ) do
      nil ->
        {:error, "Can't find user with email candidate #{email_candidate}"}

      user ->
        {:ok, user}
    end
  end

  def update_email_token(user, consent \\ nil) do
    user
    |> User.changeset(%{
      email_token: generate_email_token(),
      email_token_generated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
      email_token_validated_at: nil,
      consent_id: consent
    })
    |> Repo.update()
  end

  def update_email_candidate(user, email_candidate) do
    user
    |> User.changeset(%{
      email_candidate: email_candidate,
      email_candidate_token: generate_email_token(),
      email_candidate_token_generated_at:
        NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
      email_candidate_token_validated_at: nil
    })
    |> Repo.update()
    |> emit_event(:update_email_candidate, %{email_candidate: email_candidate})
  end

  def mark_email_token_as_validated(user) do
    validated_at =
      (user.email_token_validated_at || Timex.now())
      |> Timex.to_naive_datetime()
      |> NaiveDateTime.truncate(:second)

    user
    |> User.changeset(%{email_token_validated_at: validated_at})
    |> Repo.update()
  end

  @doc false
  def update_email(user, email) do
    # This function should be used in rare cases where we are sure the email belongs
    # to the user. One such case is Twitter OAuth where if the response contains
    # the email then it has been properly validated.
    old_email = user.email || "<no_email>"

    user
    |> User.changeset(%{email: email})
    |> Repo.update()
    |> emit_event(:update_email, %{old_email: old_email, new_email: email})
  end

  def update_email_from_email_candidate(user) do
    validated_at =
      (user.email_candidate_token_validated_at || Timex.now())
      |> Timex.to_naive_datetime()
      |> NaiveDateTime.truncate(:second)

    user
    |> User.changeset(%{
      email: user.email_candidate,
      email_candidate: nil,
      email_candidate_token_validated_at: validated_at
    })
    |> Repo.update()
    |> emit_event(:update_email, %{old_email: user.email, new_email: user.email_candidate})
  end

  @doc ~s"""
  Validate an email login token.

  A token is valid if it:
    - Matches the one stored in the users table for the user
    - Has not been used
    - Has been issues less than #{@token_valid_window_minutes} minutes ago
  """
  def email_token_valid?(user, token) do
    naive_now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    # same token, not used and still valid
    user.email_token == token and
      (user.email_token_validated_at == nil or
         abs(Timex.diff(user.email_token_validated_at, naive_now, :minutes)) <= 5) and
      abs(Timex.diff(user.email_token_generated_at, naive_now, :minutes)) <
        @token_valid_window_minutes
  end

  def email_candidate_token_valid?(user, email_candidate_token) do
    naive_now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    # same token, not used and still valid
    user.email_candidate_token == email_candidate_token and
      user.email_candidate_token_validated_at == nil and
      Timex.diff(naive_now, user.email_candidate_token_generated_at, :minutes) <
        @token_valid_window_minutes
  end

  def send_login_email(user, first_login, origin_host_parts, args \\ %{})

  def send_login_email(user, first_login, origin_host_parts, args) do
    supported_host? =
      case origin_host_parts do
        ["santiment", "net"] -> true
        [_, "santiment", "net"] -> true
        [_, "stage", "san"] -> true
        [_, "production", "san"] -> true
        _ -> false
      end

    if supported_host? do
      do_send_login_email(user, first_login, origin_host_parts, args)
    else
      {:error, "Unsupported host for email login: #{Enum.join(origin_host_parts, ".")}"}
    end
  end

  def send_login_email(user, first_login, ["santiment", "net"] = origin_host_parts, args),
    do: do_send_login_email(user, first_login, origin_host_parts, args)

  def send_login_email(user, first_login, [_, "santiment", "net"] = origin_host_parts, args),
    do: do_send_login_email(user, first_login, origin_host_parts, args)

  def send_login_email(user, first_login, [_, "stage", "san"] = origin_host_parts, args),
    do: do_send_login_email(user, first_login, origin_host_parts, args)

  def send_login_email(user, first_login, [_, "production", "san"] = origin_host_parts, args),
    do: do_send_login_email(user, first_login, origin_host_parts, args)

  def send_verify_email(user) do
    verify_link = SanbaseWeb.Endpoint.verify_url(user.email_candidate_token, user.email_candidate)
    template = Sanbase.Email.Template.verification_email_template()

    Sanbase.TemplateMailer.send(user.email_candidate, template, %{verify_link: verify_link})
  end

  defp do_send_login_email(user, first_login, origin_host_parts, args) do
    origin_url = construct_origin_url(origin_host_parts, args)
    template = Sanbase.Email.Template.choose_login_template(origin_url, first_login?: first_login)

    case generate_login_link(user, first_login, origin_url, args) do
      {:ok, login_link} ->
        Sanbase.TemplateMailer.send(user.email, template, %{login_link: login_link})

      error ->
        error
    end
  end

  defp construct_origin_url(origin_host_parts, args) do
    if Map.get(args, :is_admin_login, false) do
      SanbaseWeb.Endpoint.admin_url()
    else
      "https://" <> Enum.join(origin_host_parts, ".")
    end
  end

  defp generate_login_link(user, first_login, origin_url, args) do
    # If this is the first login that also creates the user, then
    # append signup=true to the query params
    login_url = if is_binary(origin_url), do: origin_url, else: SanbaseWeb.Endpoint.frontend_url()

    path =
      if Map.get(args, :is_admin_login, false) do
        "admin_auth/email_login"
      else
        "email_login"
      end

    login_url = Path.join(login_url, path)

    signup_map = if first_login, do: %{signup: true}, else: %{}

    query_map =
      signup_map
      |> Map.merge(%{token: user.email_token, email: user.email})
      |> Map.merge(Map.take(args, [:subscribe_to_weekly_newsletter]))

    with {:ok, query_map} <-
           add_redirect_url(query_map, :success_redirect_url, args[:success_redirect_url]),
         {:ok, query_map} <-
           add_redirect_url(query_map, :fail_redirect_url, args[:fail_redirect_url]) do
      login_link =
        URI.parse(login_url)
        |> URI.append_query(URI.encode_query(query_map))
        |> URI.to_string()

      {:ok, login_link}
    else
      error -> error
    end
  end

  def add_redirect_url(query_map, _key, nil), do: {:ok, query_map}

  def add_redirect_url(query_map, key, url) when is_binary(url) do
    with parsed <- URI.parse(url),
         "https" <- parsed.scheme,
         true <- allowed_url?(String.split(parsed.host, ".")) do
      {:ok, Map.put(query_map, key, url)}
    else
      _ -> {:error, :invalid_redirect_url, "Invalid #{key}: #{url}"}
    end
  end

  def valid_redirect_url?(_), do: false

  defp allowed_url?(["santiment", "net"]), do: true
  defp allowed_url?([_, "santiment", "net"]), do: true
  defp allowed_url?(_), do: false
end
