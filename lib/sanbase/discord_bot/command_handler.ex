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
    prompt = String.replace(msg.content, "<@#{bot_id()}>", "")

    Nostrum.Api.start_typing(thread.id)

    AiServer.route(prompt, msg.id)
    |> case do
      {:ok, "twitter", timeframe_hours, sentiment, projects} ->
        handle_ai_command(msg, prompt, thread, timeframe_hours, sentiment, projects)

      {:ok, "academy", _, _, _} ->
        answer_question(msg, thread)
    end
  end

  def handle_ai_command(msg, prompt, thread, timeframe_hours, sentiment, projects) do
    Nostrum.Api.start_typing(thread.id)

    db_params = db_params(msg, thread, "!ai")
    db_params = Map.put(db_params, :timeframe, timeframe_hours)
    db_params = Map.put(db_params, :sentiment, sentiment)
    db_params = Map.put(db_params, :projects, projects)

    {prompt, db_params} = extract_model(prompt, db_params)

    case AiContext.check_limits(db_params) do
      :ok ->
        {kw_list, ai_context} =
          AiServer.ai(prompt, db_params)
          |> process_response()

        kw_list =
          Keyword.put(kw_list, :content, Utils.trim_message(Keyword.get(kw_list, :content)))

        Nostrum.Api.create_message(thread.id, kw_list)

        if ai_context do
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

      {:error, :eserverlimit, time_left} ->
        Nostrum.Api.create_message(thread.id,
          content: "Server limit reached for today. Limit will be reset in #{time_left}."
        )

      {:error, :eprolimit, time_left} ->
        Nostrum.Api.create_message(thread.id,
          content: "Pro user limit reached for today. Limit will be reset in #{time_left}"
        )
    end
  end

  defp answer_question(msg, thread) do
    Nostrum.Api.create_message(thread.id,
      content: "Hang on <@#{to_string(msg.author.id)}> as I search our knowledge base. :robot:"
    )

    Nostrum.Api.start_typing(thread.id)

    db_params = db_params(msg, thread, "!thread")
    prompt = String.replace(msg.content, "<@#{bot_id()}>", "")
    {kw_list, ai_context} = AiServer.threaded_docs(prompt, db_params) |> process_response()

    content = Keyword.get(kw_list, :content)

    Logger.info("[id=#{msg.id}] content: #{content}")

    new_content = """
    ----------------------
    #{content}
    ----------------------
    `Note: you can ask me a follow up question by @ mentioning me again` :speech_balloon:
    ----------------------
    """

    kw_list = Keyword.put(kw_list, :content, Utils.trim_message(new_content))
    Nostrum.Api.create_message(thread.id, kw_list)

    embeds = [
      %Embed{
        description:
          "<@#{to_string(msg.author.id)}> I am still learning and improving, please let me know how I did by reactiing below"
      }
    ]

    if ai_context do
      Nostrum.Api.create_message(thread.id,
        content: "",
        embeds: embeds,
        components: [ai_context_action_row(ai_context)]
      )
    end
  end

  defp process_response({:ok, response, db}) do
    {process_response({:ok, response}), db}
  end

  defp process_response({:error, response, db}) do
    {process_response({:error, response}), db}
  end

  defp process_response({:ok, %{"answer" => "DK"}}) do
    content = "Couldn't fetch information to answer your question"

    [
      content: content,
      components: []
    ]
  end

  defp process_response({:ok, %{"type" => "search"} = response}) do
    content = """
    #{response["answer"]}
    #{response["sources"] |> format_search_sources()}
    """

    [
      content: content,
      components: []
    ]
  end

  defp process_response({:ok, response}) do
    content = """
    #{response["answer"]}
    #{response["sources"] |> format_sources()}
    """

    components =
      case Regex.run(~r/```(?:sql)?([^`]*)```/ms, content) do
        [_, matched] ->
          matched = matched |> String.trim() |> String.downcase()

          if String.starts_with?(matched, ["select", "show", "describe"]) do
            [ai_action_row()]
          else
            []
          end

        nil ->
          []
      end

    [
      content: content,
      components: components
    ]
  end

  defp process_response({:error, _error}) do
    content = "Couldn't fetch information to answer your question"

    [
      content: content,
      components: []
    ]
  end

  defp format_search_sources(sources) do
    sources |> Enum.map(fn link -> "<#{link}>" end) |> Enum.join("\n")
  end

  defp format_sources(sources) do
    sources
    |> extract_filenames_or_links_from_string()
    |> Enum.map(fn link ->
      link =
        link
        |> String.replace("src/docs/", "https://academy.santiment.net/")
        |> String.replace("index.md", "")
        |> String.replace("README.md", "https://github.com/santiment/sanpy")
        |> String.replace("/index/", "/")

      "<#{link}>"
    end)
    |> Enum.join("\n")
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

  defp extract_model(prompt, db_params) do
    model_regex = ~r/model\s*=\s*(gpt-[3,4])/

    case Regex.run(model_regex, prompt) do
      [_, model] ->
        prompt = String.replace(prompt, model_regex, "")
        db_params = Map.put(db_params, :model, String.downcase(model))
        {prompt, db_params}

      nil ->
        db_params = Map.put(db_params, :model, "gpt-4")
        {prompt, db_params}
    end
  end

  defp db_params(msg, thread, command) do
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
          is_pro?(member.roles)

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
      command: command,
      user_is_pro: user_is_pro
    }
  end

  def is_pro?(user_roles_in_santiment) do
    MapSet.intersection(MapSet.new(pro_roles()), MapSet.new(user_roles_in_santiment))
    |> Enum.any?()
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

  def ai_context_action_row(%AiContext{} = context) do
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

  def ai_context_action_row(context_id) do
    context = Sanbase.DiscordBot.AiContext.by_id(context_id)

    ai_context_action_row(context)
  end

  defp ai_action_row do
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

  def extract_thread_name(msg) do
    msg.content
    |> String.replace("<@#{bot_id()}>", "")
    |> String.slice(0, 90)
  end
end
