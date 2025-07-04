defmodule SanbaseWeb.Graphql.ChatTypes do
  use Absinthe.Schema.Notation

  import Absinthe.Resolution.Helpers
  alias SanbaseWeb.Graphql.Resolvers.ChatResolver

  enum :chat_message_role do
    value(:user)
    value(:assistant)
  end

  enum :chat_type do
    value(:dyor_dashboard)
    value(:academy_qa)
  end

  object :chat_context do
    field(:dashboard_id, :string)
    field(:asset, :string)
    field(:metrics, list_of(:string))
  end

  input_object :chat_context_input do
    field(:dashboard_id, :string)
    field(:asset, :string)
    field(:metrics, list_of(:string))
  end

  object :chat_message do
    field(:id, non_null(:id))
    field(:content, non_null(:string))
    field(:role, non_null(:chat_message_role))
    field(:context, :json)
    field(:sources, :json)
    field(:inserted_at, non_null(:datetime))
    field(:updated_at, non_null(:datetime))

    field(:chat, :chat, resolve: dataloader(SanbaseWeb.Graphql.SanbaseRepo, :chat))
  end

  object :chat do
    field(:id, non_null(:id))
    field(:title, non_null(:string))

    field :type, non_null(:chat_type) do
      resolve(fn chat, _args, _context ->
        # Convert string type to enum value
        case chat.type do
          "dyor_dashboard" -> {:ok, :dyor_dashboard}
          "academy_qa" -> {:ok, :academy_qa}
          # fallback to default
          _ -> {:ok, :dyor_dashboard}
        end
      end)
    end

    field(:inserted_at, non_null(:datetime))
    field(:updated_at, non_null(:datetime))

    field(:user, :public_user, resolve: dataloader(SanbaseWeb.Graphql.SanbaseRepo, :user))

    field :chat_messages, list_of(:chat_message) do
      resolve(&ChatResolver.chat_messages/3)
    end

    field :messages_count, :integer do
      resolve(&ChatResolver.messages_count/3)
    end

    field :latest_message, :chat_message do
      resolve(&ChatResolver.latest_message/3)
    end
  end

  object :chat_summary do
    field(:id, non_null(:id))
    field(:title, non_null(:string))

    field :type, non_null(:chat_type) do
      resolve(fn chat, _args, _context ->
        # Convert string type to enum value
        case chat.type do
          "dyor_dashboard" -> {:ok, :dyor_dashboard}
          "academy_qa" -> {:ok, :academy_qa}
          # fallback to default
          _ -> {:ok, :dyor_dashboard}
        end
      end)
    end

    field(:inserted_at, non_null(:datetime))
    field(:updated_at, non_null(:datetime))
    field(:messages_count, :integer)
    field(:latest_message, :chat_message)
  end
end
