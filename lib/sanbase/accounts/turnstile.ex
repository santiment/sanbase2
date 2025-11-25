defmodule Sanbase.Accounts.Turnstile do
  @moduledoc """
  Cloudflare Turnstile verification
  """

  require Logger

  @turnstile_verify_url "https://challenges.cloudflare.com/turnstile/v0/siteverify"

  @doc """
  Validates a Cloudflare Turnstile token.

  Returns `:ok` if the token is valid, or `{:error, reason}` if validation fails.

  ## Examples

      iex> validate("valid-token")
      :ok

      iex> validate("invalid-token")
      {:error, "Turnstile verification failed"}
  """
  @spec validate(String.t() | nil, String.t()) :: :ok | {:error, String.t()}

  def validate(nil, _remote_ip), do: {:error, "Turnstile token is missing"}

  def validate(token, remote_ip) when is_binary(token) do
    secret = System.get_env("CLOUDFLARE_TURNSTILE_SECRET_KEY")

    if is_nil(secret) or secret == "" do
      Logger.warning("CLOUDFLARE_TURNSTILE_SECRET_KEY environment variable is not set")
      {:error, "Turnstile configuration error"}
    else
      perform_verification(token, remote_ip, secret)
    end
  end

  def validate(_), do: {:error, "Invalid token format"}

  defp perform_verification(token, remote_ip, secret) do
    body = %{
      secret: secret,
      response: token,
      remoteip: remote_ip
    }

    case Req.post(@turnstile_verify_url, json: body) do
      {:ok, %Req.Response{status: 200, body: %{"success" => true}}} ->
        :ok

      {:ok, %Req.Response{status: 200, body: %{"success" => false, "error-codes" => errors}}} ->
        error_msg = "Turnstile verification failed: #{Enum.join(errors, ", ")}"
        Logger.info(error_msg)
        {:error, "Turnstile verification failed"}

      {:ok, %Req.Response{status: status}} ->
        Logger.info("Turnstile API returned unexpected status: #{status}")
        {:error, "Turnstile verification failed"}

      {:error, exception} ->
        Logger.info("Turnstile API request failed: #{inspect(exception)}")
        {:error, "Turnstile verification failed"}
    end
  end
end
