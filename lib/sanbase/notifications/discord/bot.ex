defmodule Sanbase.Notifications.Discord.Bot do
  require Mockery.Macro
  require Sanbase.Utils.Config, as: Config
  require Logger

  @discord_api_url "https://discord.com/api"
  @santiment_guild_id "334289660698427392"
  @santiment_guild_pro_role_id "532833809947951105"

  def get_user_id_by_username(username) do
    @discord_api_url
    |> Path.join("/guilds")
    |> Path.join(@santiment_guild_id)
    |> Path.join("/members/search?query=#{username}")
    |> IO.inspect()
    |> http_client().get(headers())
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        users = Jason.decode!(body)

        case length(users) do
          0 ->
            {:error, "User with this handle not found on Santiment Discord server"}

          1 ->
            user = users |> hd()

            if @santiment_guild_pro_role_id in user["roles"] do
              {:error, "You already have a PRO role in Discord"}
            else
              {:ok, user["user"]["id"]}
            end

          num when num > 1 ->
            {:error, "Please, provide the your exact handle on Santiment Discord Server"}
        end

      {:error, _} ->
        {:error, "Can't find user with this handle on our discord server"}
    end
  end

  def add_pro_role_to_user(user_id) do
    @discord_api_url
    |> Path.join("/guilds")
    |> Path.join(@santiment_guild_id)
    |> Path.join("/members")
    |> Path.join(user_id)
    |> Path.join("/roles")
    |> Path.join(@santiment_guild_pro_role_id)
    |> IO.inspect()
    |> http_client().put("", headers())
    |> case do
      {:ok, %HTTPoison.Response{status_code: 204}} ->
        {:ok, true}

      _ ->
        {:error, "Can't add your username to our Pro channel"}
    end
  end

  defp headers do
    [{"Authorization", "Bot #{discord_bot_secret()}"}]
  end

  defp discord_bot_secret do
    Config.get(:bot_secret)
  end

  defp http_client(), do: Mockery.Macro.mockable(HTTPoison)
end
