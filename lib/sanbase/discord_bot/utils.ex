defmodule Sanbase.DiscordBot.Utils do
  @moduledoc """
  Discord bot utils
  """

  @ephemeral_message_flags 64

  @spec edit_interaction_response(
          Nostrum.Struct.Interaction.t(),
          String.t(),
          list()
        ) :: {:ok, Nostrum.Struct.Message.t()} | {:error, any()}
  def edit_interaction_response(interaction, content, components) do
    Nostrum.Api.edit_interaction_response(interaction, %{
      content: trim_message(content),
      components: components
    })
  end

  @spec interaction_ack_visible(Nostrum.Struct.Interaction.t()) :: {:ok} | {:error, any()}
  def interaction_ack_visible(interaction) do
    Nostrum.Api.create_interaction_response(interaction, %{type: 5})
  end

  @spec interaction_ack(Nostrum.Struct.Interaction.t()) :: {:ok} | {:error, any()}
  def interaction_ack(interaction) do
    Nostrum.Api.create_interaction_response(interaction, %{
      type: 5,
      data: %{flags: @ephemeral_message_flags}
    })
  end

  @spec trim_message(String.t(), pos_integer()) :: String.t()
  def trim_message(message, max_length \\ 1950) do
    end_message =
      if String.starts_with?(String.trim_leading(message), "```") do
        "... (message truncated)```"
      else
        "... (message truncated)"
      end

    if String.length(message) > max_length do
      String.slice(message, 0, max_length) <> end_message
    else
      message
    end
  end
end
