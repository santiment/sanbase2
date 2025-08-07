defmodule Sanbase.Email do
  @moduledoc """
  The Email context.
  """

  alias Sanbase.Email.EmailExclusionList

  @doc """
  Checks if an email address is excluded from receiving emails.
  """
  @spec email_excluded?(String.t()) :: boolean()
  def email_excluded?(email) do
    EmailExclusionList.is_excluded?(email)
  end

  @doc """
  Adds an email to the exclusion list.
  """
  @spec exclude_email(String.t(), String.t() | nil) ::
          {:ok, EmailExclusionList.t()} | {:error, Ecto.Changeset.t()}
  def exclude_email(email, reason \\ nil) do
    EmailExclusionList.add_exclusion(email, reason)
  end

  @doc """
  Removes an email from the exclusion list.
  """
  @spec unexclude_email(String.t()) :: {:ok, EmailExclusionList.t()} | {:error, :not_found}
  def unexclude_email(email) do
    EmailExclusionList.remove_exclusion(email)
  end

  @doc """
  Gets all excluded emails.
  """
  @spec list_excluded_emails() :: [EmailExclusionList.t()]
  def list_excluded_emails do
    EmailExclusionList.list_exclusions()
  end

  @doc """
  Gets an exclusion entry by ID.
  """
  @spec get_email_exclusion(integer()) :: EmailExclusionList.t() | nil
  def get_email_exclusion(id) do
    EmailExclusionList.get_exclusion(id)
  end

  @doc """
  Updates an exclusion entry.
  """
  @spec update_email_exclusion(EmailExclusionList.t(), map()) ::
          {:ok, EmailExclusionList.t()} | {:error, Ecto.Changeset.t()}
  def update_email_exclusion(exclusion, attrs) do
    EmailExclusionList.update_exclusion(exclusion, attrs)
  end
end
