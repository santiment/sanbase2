defmodule Sanbase.DiscordBot.SupportReminder do
  def get_last_team_messages_in_threads do

    guild_id = 334289660698427392
    team_role_id = 409_637_386_012_721_155
    general_support_channel_id = 1166232322803236905
    subscription_support_channel_id = 1166255941944090644

    {:ok, result} = Nostrum.Api.list_guild_threads(guild_id)

    thread_channels =
      Enum.filter(result[:threads], fn thread ->
        thread.type == 12 and
          thread.parent_id in [general_support_channel_id, subscription_support_channel_id]
    end)

    member_cache = %{}

    Enum.map(thread_channels, fn thread_channel ->
      {:ok, messages} = Nostrum.Api.get_channel_messages(thread_channel.id, 10)
      {team_messages, _member_cache} =
        Enum.reduce(messages, {[], member_cache}, fn message, {acc, cache} ->
          user_id = message.author.id

          {member, cache} =
            case Map.get(cache, user_id) do
              nil ->
                # Fetch member from the guild
                case Nostrum.Api.get_guild_member(guild_id, user_id) do
                  {:ok, member} -> {member, Map.put(cache, user_id, member)}
                  {:error, _reason} -> {nil, cache}
                end

              member ->
                {member, cache}
            end

          # Check if the member has the @team role
          if member && Enum.any?(member.roles, fn role_id -> role_id == team_role_id end) do
            {[message | acc], cache}
          else
            {acc, cache}
          end
        end)

      # Sort the messages by timestamp to find the last one
      team_messages = Enum.sort_by(team_messages, & &1.timestamp)
      last_team_message = List.last(team_messages)

      {thread_channel, last_team_message}
    end)
  end
end
