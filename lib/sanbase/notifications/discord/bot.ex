defmodule Sanbase.Notifications.Discord.Bot do
  alias Sanbase.Utils.Config
  require Logger

  @discord_api_url "https://discord.com/api"
  @santiment_guild_id "334289660698427392"
  @santiment_guild_pro_role_id "532833809947951105"

  def add_pro_role(username) do
    with {:ok, discord_user_id} <- get_user_id_by_username(username),
         :ok <- add_pro_role_to_user(discord_user_id) do
      {:ok, true}
    end
  end

  def get_user_id_by_username(username) do
    @discord_api_url
    |> Path.join(["/guilds", @santiment_guild_id, "/members/search?query=#{username}"])
    |> HTTPoison.get(headers())
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        Jason.decode!(body)
        |> check_search_user_result()

      {:error, _} ->
        {:error, "Can't find user with this handle on our discord server"}
    end
  end

  def add_pro_role_to_user(user_id) do
    @discord_api_url
    |> Path.join([
      "/guilds",
      @santiment_guild_id,
      "/members",
      user_id,
      "/roles",
      @santiment_guild_pro_role_id
    ])
    |> HTTPoison.put("", headers())
    |> case do
      {:ok, %HTTPoison.Response{status_code: 204}} ->
        :ok

      _ ->
        {:error, "Can't add your username to our Sanbase Pro channel"}
    end
  end

  # helpers

  defp check_search_user_result(users) when is_list(users) do
    case length(users) do
      0 ->
        {:error, "User with this handle is not found on our discord server"}

      1 ->
        user = users |> hd()

        if @santiment_guild_pro_role_id in user["roles"] do
          {:error, "This username already have a PRO role in our discord server"}
        else
          {:ok, user["user"]["id"]}
        end

      num when num > 1 ->
        {:error, "Please, provide your exact handle on our discord server"}
    end
  end

  defp headers do
    [{"Authorization", "Bot #{discord_bot_secret()}"}]
  end

  defp discord_bot_secret do
    Config.module_get(__MODULE__, :bot_secret)
  end
end
