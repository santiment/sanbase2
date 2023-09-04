defmodule Sanbase.Discord.CodeHandler do
  require Logger

  alias Nostrum.Struct.Component.Button
  alias Nostrum.Struct.Component.{ActionRow, TextInput}

  alias Sanbase.Discord.AiGenCode

  @team_role_id 409_637_386_012_721_155
  @local_team_role_id 854_304_500_402_880_532

  def team_role_id do
    case Sanbase.Utils.Config.module_get(Sanbase, :deployment_env) do
      "dev" -> @local_team_role_id
      _ -> @team_role_id
    end
  end

  def handle_interaction("code", interaction, metadata) do
    interaction_ack_visible(interaction)

    [option] = interaction.data.options

    case Sanbase.OpenAI.find_or_generate_program(option.value, metadata) do
      {:ok, ai_gen_code} ->
        content = """
        🇶: #{ai_gen_code.question}

        🇦: #{ai_gen_code.answer}

        """

        edit_interaction_response(interaction, content, [action_row(ai_gen_code)])

      {:error, error} ->
        Logger.error(
          "Failed to generate program for question: #{option.value}, #{inspect(error)}"
        )

        generic_error_message(interaction)
    end
  end

  def handle_interaction("save-program", interaction, id, _metadata) do
    interaction_ack_visible(interaction)

    ai_gen_code = AiGenCode.by_id(id)

    Sanbase.OpenAI.save_program(ai_gen_code)

    content = """
    🟢 Program saved successfully!
    """

    edit_interaction_response(interaction, content, [])
  end

  def handle_interaction("show-program", interaction, id, _metadata) do
    interaction_ack_visible(interaction)

    ai_gen_code = AiGenCode.by_id(id)

    content = """
    ```python
    #{ai_gen_code.program}
    ```
    """

    edit_interaction_response(interaction, content, [action_row(ai_gen_code)])
  end

  def handle_interaction("show-program-result", interaction, id, _metadata) do
    interaction_ack_visible(interaction)

    ai_gen_code = AiGenCode.by_id(id)

    content = """
    ```
    #{ai_gen_code.program_result}
    ```
    """

    edit_interaction_response(interaction, content, [])
  end

  def handle_interaction("generate-program", interaction, id, metadata) do
    interaction_ack_visible(interaction)

    old_ai_gen_code = AiGenCode.by_id(id)

    case Sanbase.OpenAI.generate_program(old_ai_gen_code.question, metadata) do
      {:ok, ai_gen_code} ->
        content = """
        🇶: #{ai_gen_code.question}

        🇦: #{ai_gen_code.answer}

        """

        edit_interaction_response(interaction, content, [action_row(ai_gen_code)])

      {:error, error} ->
        Logger.error(
          "Failed to generate program with id #{old_ai_gen_code.id}: #{inspect(error)}"
        )

        generic_error_message(interaction)
    end
  end

  def handle_interaction("program-changes", interaction, id, metadata) do
    interaction_ack_visible(interaction)

    changes =
      interaction.data.components
      |> List.first()
      |> Map.get(:components)
      |> List.first()
      |> Map.get(:value)

    old_ai_gen_code = AiGenCode.by_id(id)

    case Sanbase.OpenAI.change_program(old_ai_gen_code, changes, metadata) do
      {:ok, ai_gen_code} ->
        content = """
        After the following changes:
        ```
        #{changes}
        ```

        🇶: #{ai_gen_code.question}

        🇦: #{ai_gen_code.answer}

        """

        edit_interaction_response(interaction, content, [action_row(ai_gen_code)])

      {:error, error} ->
        Logger.error("Failed to change program with id #{old_ai_gen_code.id}: #{inspect(error)}")
        generic_error_message(interaction)
    end
  end

  def handle_interaction("change-program-modal", interaction, id, _metadata) do
    create_modal(interaction, id)
  end

  def access_denied(interaction) do
    interaction_ack_visible(interaction)

    content =
      "You don't have access to this command. The command is available only to Santiment team members."

    edit_interaction_response(interaction, content, [])
  end

  def generic_error_message(interaction) do
    content = "An errror occured. Please try again"
    edit_interaction_response(interaction, content, [])
  end

  def discord_metadata(interaction) do
    {guild_name, channel_name} =
      Sanbase.Discord.CommandHandler.get_guild_channel(
        interaction.guild_id,
        interaction.channel_id
      )

    user_is_team_member =
      Nostrum.Api.get_guild_member(
        Sanbase.Discord.CommandHandler.santiment_guild_id(),
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
      guild_name: guild_name,
      discord_user: interaction.user.username <> interaction.user.discriminator,
      user_is_team_member: user_is_team_member
    }
  end

  # helpers
  defp edit_interaction_response(interaction, content, components) do
    Nostrum.Api.edit_interaction_response(interaction, %{
      content: trim_message(content),
      components: components
    })
  end

  defp interaction_ack_visible(interaction) do
    Nostrum.Api.create_interaction_response(interaction, %{type: 5})
  end

  def create_modal(interaction, id) do
    changes_input =
      TextInput.text_input("Changes", "changes_" <> id,
        placeholder: "What changes do you want to make?",
        style: 2,
        required: true
      )

    ar = ActionRow.action_row() |> ActionRow.put(changes_input)

    response = %{
      type: 9,
      data: %{
        custom_id: "program-changes_#{id}",
        title: "What changes do you want to make?",
        min_length: 1,
        max_length: 500,
        components: [ar]
      }
    }

    Nostrum.Api.create_interaction_response(interaction, response)
  end

  defp action_row(ai_gen_code) do
    id = to_string(ai_gen_code.id)

    show_button =
      Button.button(label: "Show program 💻", custom_id: "show-program" <> "_" <> id, style: 3)

    result_button =
      Button.button(
        label: "Program result 📜",
        custom_id: "show-program-result" <> "_" <> id,
        style: 3
      )

    change_button =
      Button.button(
        label: "Change program 🛠️",
        custom_id: "change-program-modal" <> "_" <> id,
        style: 3
      )

    gen_button =
      Button.button(
        label: "Generate new program 🤖",
        custom_id: "generate-program" <> "_" <> id,
        style: 3
      )

    save_button =
      Button.button(label: "Save program 💾", custom_id: "save-program" <> "_" <> id, style: 3)

    ActionRow.action_row()
    |> ActionRow.append(show_button)
    |> ActionRow.append(result_button)
    |> ActionRow.append(change_button)
    |> ActionRow.append(gen_button)
    |> ActionRow.append(save_button)
  end

  defp trim_message(message) do
    end_message =
      if String.starts_with?(String.trim_leading(message), "```") do
        "... (message truncated)```"
      else
        "... (message truncated)"
      end

    if String.length(message) > 1950 do
      String.slice(message, 0, 1950) <> end_message
    else
      message
    end
  end
end
