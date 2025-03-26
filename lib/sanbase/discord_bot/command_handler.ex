defmodule Sanbase.DiscordBot.CommandHandler do
  require Logger

  alias Nostrum.Struct.Embed
  alias Nostrum.Struct.Component.{Button, ActionRow}

  alias Sanbase.DiscordBot.AiServer
  alias Sanbase.DiscordBot.AiContext
  alias Sanbase.DiscordBot.Utils

  @prod_pro_roles [532_833_809_947_951_105, 409_637_386_012_721_155]
  @local_pro_roles [854_304_500_402_880_532]
  @local_guild_id 852_836_083_381_174_282
  @santiment_guild_id 334_289_660_698_427_392

  @local_bot_id 1_039_543_550_326_612_009
  @stage_bot_id 1_039_177_602_197_372_989
  @prod_bot_id 1_039_814_526_708_764_742

  @max_message_length 1950

  @team_role_id 409_637_386_012_721_155
  @local_team_role_id 854_304_500_402_880_532

  @spec team_role_id() :: integer()
  def team_role_id do
    case Sanbase.Utils.Config.module_get(Sanbase, :deployment_env) do
      "dev" -> @local_team_role_id
      _ -> @team_role_id
    end
  end

  def bot_id() do
    case Sanbase.Utils.Config.module_get(Sanbase, :deployment_env) do
      "dev" -> @local_bot_id
      "stage" -> @stage_bot_id
      _ -> @prod_bot_id
    end
  end

  def santiment_guild_id() do
    case Sanbase.Utils.Config.module_get(Sanbase, :deployment_env) do
      "dev" -> @local_guild_id
      _ -> @santiment_guild_id
    end
  end

  def pro_roles() do
    case Sanbase.Utils.Config.module_get(Sanbase, :deployment_env) do
      "dev" -> @local_pro_roles
      _ -> @prod_pro_roles
    end
  end

  # command handlers

  def handle_command("mention", msg) do
    Nostrum.Api.get_channel(msg.channel_id)
    |> case do
      {:ok, channel} ->
        channel_or_thread = maybe_create_thread(msg, channel)
        route_and_answer(msg, channel_or_thread)

      error ->
        error
    end
  end

  def handle_interaction("summary", interaction, metadata) do
    Utils.interaction_ack_visible(interaction)

    focused_option =
      interaction.data.options
      |> Enum.filter(& &1.focused)
      |> List.first()

    options_map =
      interaction.data.options |> Enum.into(%{}, fn option -> {option.name, option.value} end)

    if focused_option do
      autocomplete(interaction, focused_option.name)
    else
      with {:ok, metadata_from_options} <- metadata_from_options(options_map),
           metadata <- Map.merge(metadata, metadata_from_options),
           :ok <- check_from_to(interaction, metadata) do
        summarize_channel_or_thread(interaction, metadata, options_map)
      else
        {:error, :from_to_check} ->
          send_error_message(
            interaction,
            "The 'to' datetime should be greater than the 'from' datetime."
          )

        {:error, error} ->
          send_error_message(interaction, error)

        _ ->
          generic_error_message(interaction)
      end
    end
  end

  def handle_interaction("up", interaction, context_id) do
    discord_user = interaction.user.username <> interaction.user.discriminator
    AiContext.add_vote(context_id, %{discord_user => 1})
    respond_to_component_interaction(interaction, context_id)
  end

  def handle_interaction("down", interaction, context_id) do
    discord_user = interaction.user.username <> interaction.user.discriminator
    AiContext.add_vote(context_id, %{discord_user => -1})
    respond_to_component_interaction(interaction, context_id)
  end

  def access_denied(interaction) do
    Utils.interaction_ack_visible(interaction)

    content =
      "You don't have access to this command. The command is available only to Santiment team members."

    Utils.edit_interaction_response(interaction, content, [])
  end

  # helpers
  defp maybe_create_thread(msg, channel) do
    # already in channel type thread
    case channel.type in [10, 11, 12] do
      true ->
        channel

      false ->
        {:ok, thread_channel} = create_new_thread(msg)
        thread_channel
    end
  end

  defp create_new_thread(msg) do
    thread_name = extract_thread_name(msg)

    Nostrum.Api.start_thread_with_message(msg.channel_id, msg.id, %{
      name: thread_name,
      auto_archive_duration: 1440
    })
  end

  defp route_and_answer(msg, thread) do
    query = extract_query(msg)
    # Nostrum.Api.start_typing(thread.id)
    typing_task = Task.async(fn -> keep_typing(thread.id) end)
    discord_metadata = db_params(msg, thread)

    result = AiServer.answer(query, discord_metadata)
    Task.shutdown(typing_task, :brutal_kill)

    case result do
      {:ok, ai_context, ai_server_response} ->
        %{content: content, components: components} =
          process_ai_server_response(ai_server_response)

        msgs = content |> Utils.split_message(@max_message_length)

        msgs
        |> Enum.with_index()
        |> Enum.each(fn {msg, index} ->
          last_message? = index == length(msgs) - 1
          message_components = if last_message?, do: components, else: []
          Nostrum.Api.create_message(thread.id, content: msg, components: message_components)
        end)

        feedback_row_message(msg, thread, ai_context)

      {:error, :eserverlimit, time_left} ->
        Nostrum.Api.create_message(thread.id,
          content: "Server limit reached for today. Limit will be reset in #{time_left}."
        )

      {:error, :eprolimit, time_left} ->
        Nostrum.Api.create_message(thread.id,
          content: "Pro user limit reached for today. Limit will be reset in #{time_left}"
        )

      {:error, _} ->
        content = "Couldn't fetch information to answer your question"
        Nostrum.Api.create_message(thread.id, content: content)
    end
  end

  defp format_search_sources(sources) do
    sources = sources |> Enum.map(fn link -> "<#{link}>" end) |> Enum.join("\n")
    "Sources: \n#{sources}"
  end

  defp format_academy_sources(""), do: ""

  defp format_academy_sources(sources) do
    sources =
      sources
      |> extract_filenames_or_links_from_string()
      |> Enum.map(fn link ->
        link =
          link
          |> String.replace("src/docs/", "https://academy.santiment.net/")
          |> String.replace("index.md", "")
          |> String.replace("README.md", "https://github.com/santiment/sanpy")
          |> String.replace("/index/", "/")

        link = Regex.replace(~r/\.md$/, link, "")

        "<#{link}>"
      end)
      |> Enum.join("\n")

    "Sources: \n#{sources}"
  end

  defp extract_filenames_or_links_from_string(string) do
    string
    |> String.split(~r/,\s+/)
    |> Enum.map(fn filename ->
      case Regex.run(~r/https?:\/\/[^\s]+/, filename) do
        [link] -> link
        nil -> filename
      end
    end)
    |> Enum.filter(fn source ->
      String.contains?(source, "sanr") ||
        String.contains?(source, "sanpy") ||
        String.contains?(source, "academy") || String.contains?(source, ".md") ||
        String.contains?(source, "index")
    end)
    |> Enum.reject(&(&1 == ""))
  end

  defp db_params(msg, thread) do
    discord_user = msg.author.username <> msg.author.discriminator

    channel_name =
      case Nostrum.Api.get_channel(thread.parent_id) do
        {:ok, parent_channel} -> parent_channel.name
        _ -> nil
      end

    {guild_name, _channel_name} = get_guild_channel(msg.guild_id, msg.channel_id)

    user_is_pro =
      Nostrum.Api.get_guild_member(santiment_guild_id(), msg.author.id)
      |> case do
        {:ok, member} ->
          pro?(member.roles)

        other ->
          Logger.error("Failed to get guild member: #{inspect(other)}")
          false
      end

    %{
      discord_user: discord_user,
      guild_id: to_string(msg.guild_id),
      guild_name: guild_name,
      channel_id: to_string(msg.channel_id),
      channel_name: channel_name,
      thread_id: to_string(thread.id),
      thread_name: thread.name,
      msg_id: msg.id,
      user_is_pro: user_is_pro
    }
  end

  def pro?(user_roles_in_santiment) do
    MapSet.intersection(MapSet.new(pro_roles()), MapSet.new(user_roles_in_santiment))
    |> Enum.any?()
  end

  def discord_metadata(interaction) do
    {guild_name, channel_name} =
      get_guild_channel(
        interaction.guild_id,
        interaction.channel_id
      )

    user_is_team_member =
      Nostrum.Api.get_guild_member(
        santiment_guild_id(),
        interaction.user.id
      )
      |> case do
        {:ok, member} ->
          team_role_id() in member.roles

        other ->
          Logger.error("Failed to get guild member: #{inspect(other)}")
          false
      end

    %{
      channel: to_string(interaction.channel_id),
      guild_id: to_string(interaction.guild_id),
      channel_name: channel_name,
      is_thread: thread?(interaction.channel),
      guild_name: guild_name,
      discord_user: interaction.user.username <> interaction.user.discriminator,
      user_is_team_member: user_is_team_member
    }
  end

  defp respond_to_component_interaction(interaction, context_id) do
    Nostrum.Api.create_interaction_response(interaction.id, interaction.token, %{
      # interaction response type: UPDATE_MESSAGE*	7	for components, edit the message the component was attached to
      type: 7,
      data: %{
        components: [ai_context_action_row(context_id)]
      }
    })
  end

  defp ai_context_action_row(%AiContext{} = context) do
    ar = ActionRow.action_row()
    votes_pos = context.votes |> Enum.count(fn {_k, v} -> v == 1 end)
    votes_neg = context.votes |> Enum.count(fn {_k, v} -> v == -1 end)

    thumbs_up_button =
      Button.button(
        style: 2,
        label: "#{votes_pos}",
        custom_id: "up_#{context.id}",
        emoji: %{name: "👍"}
      )

    thumbs_down_button =
      Button.button(
        style: 2,
        label: "#{votes_neg}",
        custom_id: "down_#{context.id}",
        emoji: %{name: "👎"}
      )

    ar
    |> ActionRow.append(thumbs_up_button)
    |> ActionRow.append(thumbs_down_button)
  end

  defp ai_context_action_row(context_id) do
    context = Sanbase.DiscordBot.AiContext.by_id(context_id)

    ai_context_action_row(context)
  end

  defp run_command_action_row do
    run_button = Button.button(label: "Run 🚀", custom_id: "run", style: 3)

    ActionRow.action_row()
    |> ActionRow.append(run_button)
  end

  defp get_guild_channel(nil, _), do: {nil, nil}
  defp get_guild_channel(_, nil), do: {nil, nil}

  defp get_guild_channel(guild_id, channel_id) do
    guild_name =
      case Nostrum.Cache.GuildCache.get(guild_id) do
        {:ok, guild} ->
          guild.name

        _ ->
          case Nostrum.Api.get_guild(guild_id) do
            {:ok, guild} -> guild.name
            _ -> nil
          end
      end

    channel_name =
      case Nostrum.Cache.ChannelCache.get(channel_id) do
        {:ok, channel} ->
          channel.name

        _ ->
          case Nostrum.Api.get_channel(channel_id) do
            {:ok, channel} -> channel.name
            _ -> nil
          end
      end

    {guild_name, channel_name}
  end

  defp extract_thread_name(msg) do
    msg.content
    |> String.replace("<@#{bot_id()}>", "")
    |> String.slice(0, 90)
  end

  defp process_ai_server_response(ai_server_response) do
    case ai_server_response["answer"] do
      %{"answer" => "DK"} ->
        content = "Couldn't fetch information to answer your question"

        %{
          content: content,
          components: []
        }

      %{"type" => "search"} = answer ->
        content = """
        #{answer["answer"]}
        #{answer["sources"] |> format_search_sources()}
        """

        %{
          content: content,
          components: []
        }

      answer ->
        content = """
        #{answer["answer"]}
        #{answer["sources"] |> format_academy_sources()}
        """

        components = maybe_add_run_component(content)

        %{
          content: content,
          components: components
        }
    end
  end

  defp feedback_row_message(msg, thread, ai_context) do
    embeds = [
      %Embed{
        description:
          "<@#{to_string(msg.author.id)}> I am still learning and improving, please let me know how I did by reactiing below"
      }
    ]

    Nostrum.Api.create_message(thread.id,
      content: "",
      embeds: embeds,
      components: [ai_context_action_row(ai_context)]
    )
  end

  defp maybe_add_run_component(content) do
    case Regex.run(~r/```(?:sql)?([^`]*)```/ms, content) do
      [_, matched] ->
        matched = matched |> String.trim() |> String.downcase()

        if String.starts_with?(matched, ["select", "show", "describe"]) do
          [run_command_action_row()]
        else
          []
        end

      nil ->
        []
    end
  end

  defp extract_query(msg) do
    msg.content
    |> String.replace("<@#{bot_id()}>", "")
  end

  defp keep_typing(thread_id) do
    loop_typing(thread_id)
  end

  defp loop_typing(thread_id) do
    Nostrum.Api.start_typing(thread_id)
    :timer.sleep(7000)
    loop_typing(thread_id)
  end

  defp summarize_channel_or_thread(interaction, metadata, options_map) do
    case metadata.is_thread do
      false ->
        case AiServer.summarize_channel(
               metadata.channel,
               Map.take(metadata, [:from_dt, :to_dt])
             ) do
          {:ok, summary} ->
            content = """
            📝 Summary for channel: #{metadata.channel_name} from: `#{options_map["from_dt"]}`, to: `#{options_map["to_dt"]}`

            #{summary}
            """

            Utils.handle_interaction_response(interaction, content, [])

          {:error, error} ->
            Logger.error(
              "Failed to summarize channel: #{metadata.channel_name}, #{inspect(error)}"
            )

            generic_error_message(interaction)
        end

      true ->
        case AiServer.summarize_thread(
               metadata.channel,
               Map.take(metadata, [:from_dt, :to_dt])
             ) do
          {:ok, summary} ->
            content = """
            📝 Summary for thread: #{metadata.channel_name} from: `#{options_map["from_dt"]}`, to: `#{options_map["to_dt"]}`

            #{summary}
            """

            Utils.handle_interaction_response(interaction, content, [])

          {:error, error} ->
            Logger.error(
              "Failed to summarize thread: #{metadata.channel_name}, #{inspect(error)}"
            )

            generic_error_message(interaction)
        end

      _ ->
        generic_error_message(interaction)
    end
  end

  defp check_from_to(interaction, metadata) do
    if metadata[:to_dt] > metadata[:from_dt] do
      :ok
    else
      content = """
      The 'to' datetime should be greater than the 'from' datetime.
      """

      Utils.handle_interaction_response(interaction, content, [])

      {:error, :from_to_check}
    end
  end

  def metadata_from_options(options_map) do
    {:ok, channel} = Nostrum.Api.get_channel(options_map["channel_or_thread"])
    from_dt = text_to_datetime(options_map["from_dt"])
    to_dt = text_to_datetime(options_map["to_dt"])

    cond do
      :unsupported_datetime_representation == from_dt ->
        {:error, "Invalid `from` datetime option"}

      :unsupported_datetime_representation == to_dt ->
        {:error, "Invalid `to` datetime option"}

      true ->
        {:ok,
         %{
           channel: to_string(channel.id),
           channel_name: channel.name,
           is_thread: thread?(channel),
           from_dt: DateTime.to_unix(from_dt) |> to_string(),
           to_dt: DateTime.to_unix(to_dt) |> to_string()
         }}
    end
  end

  defp autocomplete(interaction, "from_dt") do
    choices = [
      "yesterday",
      "2 days ago",
      "3 days ago",
      "4 days ago",
      "5 days ago",
      "6 days ago",
      "last week",
      "2 weeks ago",
      "last month"
    ]

    do_autocomplete(interaction, choices)
  end

  defp autocomplete(interaction, "to_dt") do
    choices = [
      "now",
      "yesterday",
      "2 days ago",
      "3 days ago",
      "4 days ago",
      "5 days ago",
      "6 days ago",
      "last week",
      "2 weeks ago",
      "last month"
    ]

    do_autocomplete(interaction, choices)
  end

  defp do_autocomplete(interaction, choices) do
    choices = choices |> Enum.map(fn choice -> %{name: choice, value: choice} end)

    response = %{
      type: 8,
      data: %{
        choices: choices
      }
    }

    Nostrum.Api.create_interaction_response(interaction, response)
  end

  def generic_error_message(interaction) do
    content = "An errror occured. Please try again"
    Utils.edit_interaction_response(interaction, content, [])
  end

  defp text_to_datetime("now"), do: DateTime.utc_now()
  defp text_to_datetime("yesterday"), do: Timex.shift(DateTime.utc_now(), days: -1)
  defp text_to_datetime("1 day ago"), do: Timex.shift(DateTime.utc_now(), days: -1)
  defp text_to_datetime("2 days ago"), do: Timex.shift(DateTime.utc_now(), days: -2)
  defp text_to_datetime("3 days ago"), do: Timex.shift(DateTime.utc_now(), days: -3)
  defp text_to_datetime("4 days ago"), do: Timex.shift(DateTime.utc_now(), days: -4)
  defp text_to_datetime("5 days ago"), do: Timex.shift(DateTime.utc_now(), days: -5)
  defp text_to_datetime("6 days ago"), do: Timex.shift(DateTime.utc_now(), days: -6)
  defp text_to_datetime("last week"), do: Timex.shift(DateTime.utc_now(), weeks: -1)
  defp text_to_datetime("last 2 weeks"), do: Timex.shift(DateTime.utc_now(), weeks: -14)
  defp text_to_datetime("last month"), do: Timex.shift(DateTime.utc_now(), months: -1)
  defp text_to_datetime(_), do: :unsupported_datetime_representation

  defp thread?(%Nostrum.Struct.Channel{type: 11}) do
    true
  end

  defp thread?(_), do: false

  defp send_error_message(interaction, error) do
    content = """
    #{error}
    """

    Utils.handle_interaction_response(interaction, content, [])
  end
end
