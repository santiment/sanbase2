defmodule Sanbase.Email.NewsletterToken do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  alias Sanbase.Repo
  alias Sanbase.Accounts.User.Email

  # Email verification links will be valid 24 hours
  @login_email_valid_minutes 24 * 60

  schema "newsletter_tokens" do
    field(:email, :string)
    field(:email_token_generated_at, :utc_datetime)
    field(:email_token_validated_at, :utc_datetime)
    field(:token, :string)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(newsletter_token, attrs) do
    newsletter_token
    |> cast(attrs, [:token, :email, :email_token_generated_at, :email_token_validated_at])
    |> validate_required([:token, :email, :email_token_generated_at, :email_token_validated_at])
    |> unique_constraint(:email, name: :email_token_uk)
  end

  def get_by(email, token) do
    Repo.get_by(__MODULE__, email: email, token: token)
  end

  # Limits for the public verify mutation, per recipient (case-insensitive).
  @min_seconds_between_tokens 60
  @max_tokens_per_day 5

  @doc ~s"""
  True if no more verification tokens may be generated for this email right now:
  one was generated in the last #{@min_seconds_between_tokens} seconds, or
  #{@max_tokens_per_day} were generated in the last 24 hours.
  Used to stop the public verify mutation from mail-bombing one address.

  It is a read, so callers that insert a token afterwards must serialize on the
  email (see `SanbaseWeb.Graphql.Resolvers.EmailResolver`).
  """
  def generation_limit_reached?(email) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    minute_ago = DateTime.add(now, -@min_seconds_between_tokens, :second)
    day_ago = DateTime.add(now, -24 * 60 * 60, :second)

    email = String.downcase(email)

    {last_minute, last_day} =
      from(t in __MODULE__,
        where: fragment("lower(?)", t.email) == ^email and t.email_token_generated_at > ^day_ago,
        select:
          {fragment("count(*) FILTER (WHERE ? > ?)", t.email_token_generated_at, ^minute_ago),
           count(t.id)}
      )
      |> Repo.one()

    last_minute > 0 or last_day >= @max_tokens_per_day
  end

  def create_email_token(email) do
    %__MODULE__{}
    |> change(
      email: email,
      token: Email.generate_email_token(),
      email_token_generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
      email_token_validated_at: nil
    )
    |> validate_change(:email, fn :email, email ->
      if Sanbase.Utils.Email.valid_email?(email), do: [], else: [email: "is invalid"]
    end)
    |> Repo.insert()
  end

  def mark_email_token_as_validated(newsletter_token) do
    newsletter_token
    |> change(email_token_validated_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
  end

  def verify_token(email, token) do
    get_by(email, token)
    |> check_and_mark_valid_token()
  end

  def send_email(%__MODULE__{email: email, token: token}) do
    verify_link = verify_url(token, email, "weekly_digest")
    template = Sanbase.Email.Template.verification_email_template()

    Sanbase.TemplateMailer.send(email, template, %{verify_link: verify_link})
  end

  # helpers
  defp check_and_mark_valid_token(nil), do: {:error, :newsletter_token_invalid}

  defp check_and_mark_valid_token(
         %__MODULE__{
           email_token_generated_at: email_token_generated_at,
           email_token_validated_at: email_token_validated_at
         } = newsletter_token
       ) do
    if is_nil(email_token_validated_at) &&
         Timex.diff(Timex.now(), email_token_generated_at, :minutes) <
           @login_email_valid_minutes do
      mark_email_token_as_validated(newsletter_token)
    else
      {:error, :newsletter_token_expired}
    end
  end

  defp check_and_mark_valid_token(_), do: {:error, :unknown}

  defp verify_url(token, email, type) do
    SanbaseWeb.Endpoint.frontend_url() <>
      "/subscribe_email?" <>
      URI.encode_query(token: token, email: email, type: type)
  end
end
