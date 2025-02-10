defmodule SanbaseWeb.Graphql.Middlewares.Helpers do
  @moduledoc ~s"""
  Common functions used among multiple middlewares
  """

  alias Absinthe.Resolution
  alias Sanbase.Accounts.User

  @doc ~s"""
  Decides whether the user has access or not.

  The `opts` can contain different checks that are applied in order, and if any
  of them fails, an error is returned:
    - `access_by_email_pattern: regex` - checks if the user's email matches the given
      pattern regex
    - `allow_access_without_terms_accepted: boolean` - checks if the user has accepted
      the privacy policy

  In case one check fails, the resolution field is returned with the error tuple
  put in as result, which stops further execution of the query/mutation and returns the error
  to the caller.
  """
  @spec handle_user_access(
          resolution :: Resolution.t(),
          current_user :: %User{},
          opts :: Keyword.t()
        ) :: Resolution.t()
  def handle_user_access(resolution, %User{} = user, opts) do
    with true <- access_without_terms_accepted?(user, opts),
         true <- access_by_email_pattern?(user, opts) do
      resolution
    else
      {:error, _message} = error_tuple ->
        Resolution.put_result(resolution, error_tuple)
    end
  end

  # Private functions

  defp access_by_email_pattern?(%User{email: email}, opts) do
    pattern = Keyword.get(opts, :access_by_email_pattern)

    if is_nil(pattern) or (not is_nil(email) and String.match?(email, pattern)) do
      true
    else
      {:error, "Access denied. Your email does not match the required pattern."}
    end
  end

  defp access_without_terms_accepted?(%User{} = user, opts) do
    allow_access_without = Keyword.get(opts, :allow_access_without_terms_accepted, false)
    %User{privacy_policy_accepted: privacy_policy_accepted} = user

    if allow_access_without || privacy_policy_accepted do
      true
    else
      {:error, "Access denied. Accept the privacy policy to activate your account."}
    end
  end
end
