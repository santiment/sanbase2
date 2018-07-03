defmodule SanbaseWeb.Graphql.Resolvers.AccountResolver do
  require Logger

  alias SanbaseWeb.Graphql.Helpers.Utils
  alias Sanbase.Auth.{User, EthAccount}
  alias Sanbase.InternalServices.Ethauth
  alias Sanbase.Model.{Project, UserFollowedProject}
  alias Sanbase.Auth.{User, EthAccount}
  alias Sanbase.Repo
  alias Ecto.Multi

  import Ecto.Query

  def san_balance(
        %User{san_balance: san_balance, test_san_balance: test_san_balance},
        _args,
        _res
      ) do
    {:ok, Decimal.to_float(test_san_balance || san_balance || Decimal.new(0))}
  end

  def current_user(_root, _args, %{
        context: %{auth: %{auth_method: :user_token, current_user: user}}
      }) do
    {:ok, user}
  end

  def current_user(_root, _args, _context), do: {:ok, nil}

  def eth_login(
        %{signature: signature, address: address, message_hash: message_hash} = args,
        _resolution
      ) do
    with true <- Ethauth.verify_signature(signature, address, message_hash),
         {:ok, user} <- fetch_user(args, Repo.get_by(EthAccount, address: address)),
         {:ok, token, _claims} <- SanbaseWeb.Guardian.encode_and_sign(user, %{salt: user.salt}) do
      {:ok, %{user: user, token: token}}
    else
      {:error, reason} ->
        Logger.warn("Login failed: #{reason}")

        {:error, message: "Login failed"}

      _ ->
        Logger.warn("Login failed: invalid signature")
        {:error, message: "Login failed"}
    end
  end

  def email_login(%{email: email} = args, _resolution) do
    with {:ok, user} <- User.find_or_insert_by_email(email, args[:username]),
         {:ok, user} <- User.update_email_token(user, args[:consent]),
         {:ok, _user} <- User.send_login_email(user) do
      {:ok, %{success: true}}
    else
      _ -> {:error, message: "Can't login"}
    end
  end

  def email_login_verify(%{token: token, email: email}, _resolution) do
    with {:ok, user} <- User.find_or_insert_by_email(email),
         true <- User.email_token_valid?(user, token),
         {:ok, token, _claims} <- SanbaseWeb.Guardian.encode_and_sign(user, %{salt: user.salt}),
         {:ok, user} <- User.mark_email_token_as_validated(user) do
      {:ok, %{user: user, token: token}}
    else
      _ -> {:error, message: "Login failed"}
    end
  end

  def change_email(_root, %{email: new_email}, %{
        context: %{auth: %{auth_method: :user_token, current_user: user}}
      }) do
    Repo.get!(User, user.id)
    |> User.changeset(%{email: new_email})
    |> Repo.update()
    |> case do
      {:ok, user} ->
        {:ok, user}

      {:error, changeset} ->
        {
          :error,
          message: "Cannot update current user's email to #{new_email}",
          details: Utils.error_details(changeset)
        }
    end
  end

  def change_username(_root, %{username: new_username}, %{
        context: %{auth: %{auth_method: :user_token, current_user: user}}
      }) do
    Repo.get!(User, user.id)
    |> User.changeset(%{username: new_username})
    |> Repo.update()
    |> case do
      {:ok, user} ->
        {:ok, user}

      {:error, changeset} ->
        {
          :error,
          message: "Cannot update current user's username to #{new_username}",
          details: Utils.error_details(changeset)
        }
    end
  end

  def unfollow_project(_root, %{project_id: project_id}, %{
        context: %{auth: %{auth_method: :user_token, current_user: user}}
      }) do
    from(
      pair in UserFollowedProject,
      where: pair.project_id == ^project_id and pair.user_id == ^user.id
    )
    |> Repo.delete_all()

    {:ok, user}
  end

  def follow_project(_root, %{project_id: project_id}, %{
        context: %{auth: %{auth_method: :user_token, current_user: user}}
      }) do
    with %Project{} <- Repo.get(Project, project_id) do
      %UserFollowedProject{project_id: project_id, user_id: user.id}
      |> UserFollowedProject.changeset(%{project_id: project_id, user_id: user.id})
      |> Repo.insert(on_conflict: :nothing)
      |> case do
        {:ok, _} ->
          {:ok, user}

        {:error, changeset} ->
          {
            :error,
            message: "Cannot follow project with id #{project_id}",
            details: Utils.error_details(changeset)
          }
      end
    else
      _ ->
        {:error, message: "Project with the given ID does not exist."}
    end
  end

  def followed_projects(_root, _args, %{
        context: %{auth: %{auth_method: :user_token, current_user: user}}
      }) do
    query =
      from(
        p in Project,
        inner_join: ufp in UserFollowedProject,
        on: p.id == ufp.project_id,
        where: ufp.user_id == ^user.id
      )

    {:ok, Repo.all(query)}
  end

  def followed_projects(_root, _args, _resolution) do
    {:error, "You must be logged in to fetch followed projects"}
  end

  def update_terms_and_conditions(_root, args, %{
        context: %{auth: %{auth_method: :user_token, current_user: user}}
      }) do
    # Update only the provided arguments
    args =
      args
      |> Enum.reject(fn {_key, value} -> value == nil end)
      |> Enum.into(%{})

    Repo.get!(User, user.id)
    |> User.changeset(args)
    |> Repo.update()
    |> case do
      {:ok, user} ->
        {:ok, user}

      {:error, changeset} ->
        {
          :error,
          message: "Cannot update current user's terms and conditions",
          details: Utils.error_details(changeset)
        }
    end
  end

  # Private functions

  # No eth account and there is a user logged in
  defp fetch_user(
         %{address: address, context: %{auth: %{auth_method: :user_token, current_user: user}}},
         nil
       ) do
    %EthAccount{user_id: user.id, address: address}
    |> Repo.insert!()

    {:ok, user}
  end

  # No eth account and no user logged in
  defp fetch_user(%{address: address}, nil) do
    Multi.new()
    |> Multi.insert(
      :add_user,
      User.changeset(%User{}, %{username: address, salt: User.generate_salt()})
    )
    |> Multi.run(:add_eth_account, fn %{add_user: %User{id: id}} ->
      eth_account =
        EthAccount.changeset(%EthAccount{}, %{user_id: id, address: address})
        |> Repo.insert()

      {:ok, eth_account}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{add_user: user}} -> {:ok, user}
      {:error, _, reason, _} -> {:error, message: reason}
    end
  end

  # Existing eth account, login as the user of the eth account
  defp fetch_user(_, %EthAccount{user_id: user_id}) do
    {:ok, Repo.get!(User, user_id)}
  end
end
