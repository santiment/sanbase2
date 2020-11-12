defmodule Sanbase.Auth.User.Email do
  import Ecto.Changeset

  alias Sanbase.Repo
  alias Sanbase.Auth.User

  # The Login links will be valid 1 hour
  @login_email_valid_minutes 60

  # The login link will be valid for 10
  @login_email_valid_after_validation_minutes 10

  require Mockery.Macro
  defp mandrill_api(), do: Mockery.Macro.mockable(Sanbase.MandrillApi)

  def find_or_insert_by_email(email, username \\ nil) do
    email = String.downcase(email)

    case Repo.get_by(User, email: email) do
      nil ->
        %User{email: email, username: username, salt: User.generate_salt(), first_login: true}
        |> Repo.insert()

      user ->
        {:ok, user}
    end
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
    |> change(
      email_token: User.generate_email_token(),
      email_token_generated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second),
      email_token_validated_at: nil,
      consent_id: consent
    )
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
    |> change(
      email_token_validated_at: validated_at,
      is_registered: true
    )
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

    cond do
      user.email_token != token ->
        false

      Timex.diff(naive_now, user.email_token_generated_at, :minutes) >
          @login_email_valid_minutes ->
        false

      user.email_token_validated_at == nil ->
        true

      Timex.diff(naive_now, user.email_token_validated_at, :minutes) >
          @login_email_valid_after_validation_minutes ->
        false

      true ->
        true
    end
  end

  def email_candidate_token_valid?(user, email_candidate_token) do
    naive_now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    cond do
      user.email_candidate_token != email_candidate_token ->
        false

      Timex.diff(naive_now, user.email_candidate_token_generated_at, :minutes) >
          @login_email_valid_minutes ->
        false

      user.email_candidate_token_validated_at == nil ->
        true

      Timex.diff(naive_now, user.email_candidate_token_validated_at, :minutes) >
          @login_email_valid_after_validation_minutes ->
        false

      true ->
        true
    end
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
