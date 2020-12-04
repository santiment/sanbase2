defmodule Sanbase.Auth.User.Email do
  alias Sanbase.Repo
  alias Sanbase.Auth.User

  @token_valid_window_minutes 60

  require Mockery.Macro
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
  end

  def mark_email_token_as_validated(user) do
    validated_at =
      (user.email_token_validated_at || Timex.now())
      |> Timex.to_naive_datetime()
      |> NaiveDateTime.truncate(:second)

    user
    |> User.changeset(%{
      email_token_validated_at: validated_at,
      is_registered: true
    })
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
  end

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

  def send_login_email(user, origin_url, args \\ %{}) do
    origin_url
    |> Sanbase.Email.Template.choose_login_template(first_login?: user.first_login)
    |> mandrill_api().send(user.email, %{
      LOGIN_LINK: SanbaseWeb.Endpoint.login_url(user.email_token, user.email, origin_url, args)
    })
  end

  def send_verify_email(user) do
    mandrill_api().send(
      Sanbase.Email.Template.verification_email_template(),
      user.email_candidate,
      %{
        VERIFY_LINK:
          SanbaseWeb.Endpoint.verify_url(user.email_candidate_token, user.email_candidate)
      }
    )
  end
end
