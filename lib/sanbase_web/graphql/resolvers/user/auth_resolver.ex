defmodule SanbaseWeb.Graphql.Resolvers.AuthResolver do
  alias Sanbase.Accounts.Auth

  def get_auth_sessions(_root, _args, %{context: %{auth: %{current_user: user}} = context}) do
    refresh_token = context[:jwt_tokens][:refresh_token]

    SanbaseWeb.Guardian.Token.refresh_tokens(user.id, refresh_token)
  end

  def revoke_current_refresh_token(_root, _args, %{context: %{jwt_tokens: jwt_tokens}}) do
    case Map.get(jwt_tokens, :refresh_token) do
      nil ->
        {:ok, true}

      refresh_token ->
        {:ok, _} = SanbaseWeb.Guardian.revoke(refresh_token)
        {:ok, true}
    end
  end

  def revoke_refresh_token(
        _root,
        %{refresh_token_jti: jti},
        %{context: %{auth: %{current_user: user}}}
      ) do
    case SanbaseWeb.Guardian.Token.revoke(jti, user.id) do
      :ok -> {:ok, true}
      _ -> {:ok, false}
    end
  end

  def revoke_all_refresh_tokens(_root, _args, %{context: %{auth: %{current_user: user}}}) do
    case SanbaseWeb.Guardian.Token.revoke_all_with_user_id(user.id) do
      {:ok, _} -> {:ok, true}
      _ -> {:error, false}
    end
  end

  def eth_login(_root, args, %{context: %{device_data: device_data, origin_url: origin_url}}) do
    Auth.eth_login(args, %{device_data: device_data, origin_url: origin_url})
  end

  def send_email_login_email(args, %{
        context: %{
          origin_url: origin_url,
          origin_host_parts: origin_host_parts,
          remote_ip: remote_ip
        }
      }) do
    Auth.send_login_email(args, %{
      origin_url: origin_url,
      origin_host_parts: origin_host_parts,
      remote_ip: remote_ip
    })
  end

  def email_login_verify(args, %{context: %{device_data: device_data, origin_url: origin_url}}) do
    Auth.verify_email_login(args, %{device_data: device_data, origin_url: origin_url})
  end

  def change_email(_root, %{email: email_candidate}, %{
        context: %{
          remote_ip: remote_ip,
          auth: %{auth_method: :user_token, current_user: user}
        }
      }) do
    Auth.change_email_request(user, email_candidate, remote_ip)
  end

  def email_change_verify(args, %{context: %{device_data: device_data}}) do
    Auth.verify_email_change(args, %{device_data: device_data})
  end
end
