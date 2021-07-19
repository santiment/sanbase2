defmodule Sanbase.Accounts.User.Email do
  alias Sanbase.Repo
  alias Sanbase.Accounts.User

  import Sanbase.Accounts.EventEmitter, only: [emit_event: 3]

  require Mockery.Macro

  @token_valid_window_minutes 60

  defp mandrill_api(), do: Mockery.Macro.mockable(Sanbase.MandrillApi)

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
      email_token: User.generate_email_token(),
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
      email_candidate_token: User.generate_email_token(),
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
      user.email_token_validated_at == nil and
      Timex.diff(naive_now, user.email_token_generated_at, :minutes) < @token_valid_window_minutes
  end

  def email_candidate_token_valid?(user, email_candidate_token) do
    naive_now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    # same token, not used and still valid
    user.email_candidate_token == email_candidate_token and
      user.email_candidate_token_validated_at == nil and
      Timex.diff(naive_now, user.email_candidate_token_generated_at, :minutes) <
        @token_valid_window_minutes
  end

  def send_login_email(user, [_, "santiment", "net"] = origin_host_parts, args \\ %{}) do
    origin_url = "https://" <> Enum.join(origin_host_parts, ".")

    origin_url
    |> Sanbase.Email.Template.choose_login_template(first_login?: user.first_login)
    |> mandrill_api().send(
      user.email,
      %{LOGIN_LINK: generate_login_link(user, origin_host_parts, args)},
      %{subaccount: "login-emails"}
    )
  end

  def send_verify_email(user) do
    mandrill_api().send(
      Sanbase.Email.Template.verification_email_template(),
      user.email_candidate,
      %{
        VERIFY_LINK:
          SanbaseWeb.Endpoint.verify_url(user.email_candidate_token, user.email_candidate)
      },
      %{subaccount: "login-emails"}
    )
  end

  defp generate_login_link(user, origin_host_parts, args) do
    [origin_app, "santiment", "net"] = origin_host_parts
    origin_url = "https://#{origin_app}.santiment.net"
    SanbaseWeb.Endpoint.login_url(user.email_token, user.email, origin_url, args)
  end
end
