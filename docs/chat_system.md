# Chat System Documentation

## Overview

The Chat system provides a complete conversation interface where users can interact with AI assistants in contextual discussions. Each chat belongs to a user and contains multiple messages with roles (user/assistant) and contextual information.

## Database Schema

### Tables

#### `chats`
- `id` (binary_id, primary key) - Unique chat identifier
- `title` (string, required) - Chat title (max 255 chars, generated from first message)
- `user_id` (binary_id, foreign key) - Reference to owning user
- `inserted_at`, `updated_at` (timestamps)

#### `chat_messages`
- `id` (binary_id, primary key) - Unique message identifier  
- `chat_id` (binary_id, foreign key) - Reference to parent chat
- `content` (text, required) - Message content
- `role` (enum: :user, :assistant) - Message author role
- `context` (map) - Contextual metadata (dashboard_id, asset, metrics)
- `inserted_at`, `updated_at` (timestamps)

### Indexes
- `user_id` for efficient user chat lookups
- `chat_id` for message retrieval
- `inserted_at` for chronological ordering
- `role` for filtering by message type

## Core Modules

### Context Layer

#### `Sanbase.Chat`
Main context module providing:
- `create_chat_with_message/3` - Creates chat with initial user message
- `create_chat/1` - Creates empty chat
- `add_message_to_chat/4` - Adds message with role and context
- `add_assistant_response/3` - Convenience for AI responses
- `get_chat_with_messages/1` - Retrieves chat with preloaded messages
- `list_user_chats/1` - Lists user's chats (ordered by updated_at desc)
- `delete_chat/1`, `update_chat_title/2` - Chat management
- `get_chat_messages/2` - Paginated message retrieval

### Schema Modules

#### `Sanbase.Chat.Chat`
- Binary ID primary key
- Belongs to user, has many chat_messages
- Title validation (max 255 chars)
- Messages preloaded and ordered by inserted_at

#### `Sanbase.Chat.ChatMessage`  
- Binary ID primary key
- Ecto.Enum for role validation
- Custom context validation for dashboard_id/asset/metrics
- Belongs to chat

## GraphQL API

### Types

#### `:chat`
```graphql
type Chat {
  id: ID!
  title: String!
  insertedAt: DateTime!
  updatedAt: DateTime!
  user: PublicUser
  chatMessages: [ChatMessage!]
  messagesCount: Int
  latestMessage: ChatMessage
}
```

#### `:chat_message`
```graphql
type ChatMessage {
  id: ID!
  content: String!
  role: ChatMessageRole!
  context: JSON
  insertedAt: DateTime!
  updatedAt: DateTime!
  chat: Chat
}

enum ChatMessageRole {
  USER
  ASSISTANT
}
```

#### `:chat_summary`
Lightweight chat representation for list views with messages count and latest message.

### Mutations

#### `sendChatMessage`
```graphql
mutation {
  sendChatMessage(input: {
    chatId: ID          # Optional: creates new chat if not provided
    content: String!    # Required: message content  
    context: {          # Optional: contextual metadata
      dashboardId: String
      asset: String
      metrics: [String]
    }
  }) {
    # Returns full Chat object
  }
}
```

**Behavior:**
- If `chatId` not provided: Creates new chat with user message
- If `chatId` provided: Adds user message to existing chat
- All API messages have role `:user` (assistant responses added via backend)
- Context is validated and stored as map
- Returns complete chat with all messages

#### `deleteChat`
```graphql
mutation {
  deleteChat(id: ID!) {
    # Returns deleted Chat object
  }
}
```

### Queries

#### `myChats`
```graphql
query {
  myChats {
    # Returns [ChatSummary] ordered by most recent activity
  }
}
```

#### `chat`
```graphql
query {
  chat(id: ID!) {
    # Returns full Chat with all messages
  }
}
```

#### `chatMessages`
```graphql
query {
  chatMessages(
    chatId: ID!
    limit: Int = 50
    offset: Int = 0
  ) {
    # Returns paginated [ChatMessage]
  }
}
```

## Usage Examples

### Creating New Conversation
```graphql
mutation {
  sendChatMessage(input: {
    content: "What are Bitcoin's key metrics?"
    context: {
      asset: "bitcoin"
      metrics: ["price_usd", "volume_usd"]
    }
  }) {
    id
    title
    chatMessages {
      content
      role
      context
    }
  }
}
```

### Continuing Conversation
```graphql
mutation {
  sendChatMessage(input: {
    chatId: "existing-chat-id"
    content: "How about Ethereum?"
    context: {
      asset: "ethereum"
    }
  }) {
    chatMessages {
      content
      role
    }
  }
}
```

### Retrieving Chat History
```graphql
query {
  myChats {
    id
    title
    messagesCount
    latestMessage {
      content
      insertedAt
    }
  }
}
```

## Security & Authorization

- All operations require JWT authentication
- Users can only access their own chats
- Access control enforced at resolver level
- Database foreign key constraints ensure data integrity

## Business Logic

### Title Generation
- Auto-generated from first message content
- Truncated to 50 characters with "..." suffix if needed
- Updates on chat creation only

### Context Handling
- Flexible map structure for metadata
- Common fields: dashboard_id, asset, metrics
- Validated at schema level for known fields
- Stored as JSON in database

### Message Ordering
- Messages ordered by `inserted_at` chronologically
- Efficient retrieval with database indexes
- Pagination support for large conversations

## Testing

Comprehensive test coverage includes:
- **Context Layer Tests** (`test/sanbase/chat_test.exs`): 25 tests covering business logic
- **GraphQL API Tests** (`test/sanbase_web/graphql/chat/chat_api_test.exs`): 20 tests covering API behavior
- End-to-end workflow testing
- Error handling and edge cases
- Authentication and authorization

## Integration Points

### Dataloader Configuration
- Configured in `SanbaseWeb.Graphql.SanbaseRepo` 
- Preloads user and chat_messages for efficient GraphQL resolution
- Supports nested queries without N+1 problems

### User Association
- Chat field added to User type via resolver
- Returns chat summaries for user's chats
- Integrated with existing user authentication system 