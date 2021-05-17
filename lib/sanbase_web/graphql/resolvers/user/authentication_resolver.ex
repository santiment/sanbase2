defmodule SanbaseWeb.Graphql.Resolvers.AuthenticationResolver do
  alias Sanbase.InternalServices.Ethauth
  alias Sanbase.Accounts.{User, EthAccount}
  alias Sanbase.Billing

  require Logger

  def revoke_refresh_token(_root, _args, %{context: %{auth: %{current_user: current_user}}}) do
  end

  def eth_login(
        _root,
        %{signature: signature, address: address, message_hash: message_hash} = args,
        _resolution
      ) do
    with true <- address_message_hash(address) == message_hash,
         true <- Ethauth.verify_signature(signature, address, message_hash),
         {:ok, user} <- fetch_user(args, EthAccount.by_address(address)),
         {:ok, %{} = jwt_tokens_map} <- SanbaseWeb.Guardian.get_jwt_tokens(user),
         _ <- Billing.maybe_create_liquidity_or_trial_subscription(user.id),
         {:ok, user} <- User.mark_as_registered(user, %{login_origin: :eth_login}) do
      {:ok,
       %{
         user: user,
         token: jwt_tokens_map.access_token,
         access_token: jwt_tokens_map.access_token,
         refresh_token: jwt_tokens_map.refresh_token
       }}
    else
      {:error, reason} ->
        Logger.warn("Login failed: #{reason}")
        {:error, message: "Login failed"}

      _ ->
        Logger.warn("Login failed: invalid signature")
        {:error, message: "Login failed"}
    end
  end

  def email_login(%{email: email} = args, %{
        context: %{origin_url: origin_url}
      }) do
    with {:ok, user} <- User.find_or_insert_by(:email, email, %{username: args[:username]}),
         {:ok, user} <- User.update_email_token(user, args[:consent]),
         {:ok, _user} <- User.send_login_email(user, origin_url, args) do
      {:ok, %{success: true, first_login: user.first_login}}
    else
      _ -> {:error, message: "Can't login"}
    end
  end

  def email_login_verify(%{token: token, email: email}, _resolution) do
    with {:ok, user} <- User.find_or_insert_by(:email, email),
         true <- User.email_token_valid?(user, token),
         {:ok, %{} = jwt_tokens_map} <- SanbaseWeb.Guardian.get_jwt_tokens(user),
         {:ok, user} <- User.mark_email_token_as_validated(user),
         _ <- Billing.maybe_create_liquidity_or_trial_subscription(user.id),
         {:ok, user} <- User.mark_as_registered(user, %{login_origin: :email}) do
      {:ok,
       %{
         user: user,
         token: jwt_tokens_map.access_token,
         access_token: jwt_tokens_map.access_token,
         refresh_token: jwt_tokens_map.refresh_token
       }}
    else
      _ -> {:error, message: "Login failed"}
    end
  end

  # No eth account and there is a user logged in

  defp fetch_user(
         %{address: address, context: %{auth: %{auth_method: :user_token, current_user: user}}},
         nil
       ) do
    _ = EthAccount.create(%{user_id: user.id, address: address})

    {:ok, user}
  end

  # No eth account and no user logged in
  defp fetch_user(%{address: address}, nil) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(
      :add_user,
      User.changeset(%User{}, %{
        username: address,
        salt: User.generate_salt(),
        first_login: true
      })
    )
    |> Ecto.Multi.run(:add_eth_account, fn _repo, %{add_user: %User{id: id}} ->
      eth_account =
        EthAccount.changeset(%EthAccount{}, %{user_id: id, address: address})
        |> Sanbase.Repo.insert()

      {:ok, eth_account}
    end)
    |> Sanbase.Repo.transaction()
    |> case do
      {:ok, %{add_user: user}} ->
        {:ok, user}

      {:error, _, reason, _} ->
        {:error, message: reason}
    end
  end

  # Existing eth account, login as the user of the eth account
  defp fetch_user(_, %EthAccount{user_id: user_id}) do
    User.by_id(user_id)
  end

  defp address_message_hash(address) do
    message = "Login in Santiment with address #{address}"
    full_message = "\x19Ethereum Signed Message:\n" <> "#{String.length(message)}" <> message
    {:ok, hash} = ExKeccak.hash_256(full_message)
    "0x" <> Base.encode16(hash, case: :lower)
  end
end
