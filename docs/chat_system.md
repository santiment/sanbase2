# Chat System Documentation

## Overview

The Chat system provides a complete conversation interface where both authenticated users and anonymous visitors can interact with AI assistants in contextual discussions. Chats can be owned by authenticated users or be anonymous (accessible to anyone with the chat ID), and contain multiple messages with roles (user/assistant) and contextual information.

## Database Schema

### Tables

#### `chats`
- `id` (binary_id, primary key) - Unique chat identifier
- `title` (string, required) - Chat title (max 255 chars, generated from first message)
- `type` (string, required, default: "dyor_dashboard") - Chat type for different UI contexts
- `user_id` (binary_id, foreign key, nullable) - Reference to owning user (null for anonymous chats)
- `inserted_at`, `updated_at` (timestamps)

#### `chat_messages`
- `id` (binary_id, primary key) - Unique message identifier  
- `chat_id` (binary_id, foreign key) - Reference to parent chat
- `content` (text, required) - Message content
- `role` (enum: :user, :assistant) - Message author role
- `context` (map) - Contextual metadata (dashboard_id, asset, metrics)
- `sources` (array of maps) - Academy QA source references with title, URL, similarity
- `inserted_at`, `updated_at` (timestamps)

### Indexes
- `user_id` for efficient user chat lookups
- `chat_id` for message retrieval
- `inserted_at` for chronological ordering
- `role` for filtering by message type
- `type` for filtering chats by type
- `chats_user_id_updated_at_index` for efficient cleanup operations
- `chats_anonymous_updated_at_index` for anonymous chat management and cleanup

## Core Modules

### Context Layer

#### `Sanbase.Chat`
Main context module providing:
- `create_chat_with_message/4` - Creates chat with initial user message and optional type (supports nil user_id for anonymous)
- `create_chat/1` - Creates empty chat (defaults to "dyor_dashboard" type)
- `add_message_to_chat/4` - Adds message with role and context
- `add_assistant_response/3` - Convenience for AI responses
- `add_assistant_response_with_sources/4` - AI responses with Academy QA sources
- `get_chat_with_messages/1` - Retrieves chat with preloaded messages
- `list_user_chats/1` - Lists user's chats (returns empty list for nil user_id)
- `delete_chat/1`, `update_chat_title/2` - Chat management
- `get_chat_messages/2` - Paginated message retrieval

### Schema Modules

#### `Sanbase.Chat.Chat`
- Binary ID primary key
- Belongs to user, has many chat_messages
- Title validation (max 255 chars)
- Type validation (must be "dyor_dashboard")
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
  type: ChatType!
  insertedAt: DateTime!
  updatedAt: DateTime!
  user: PublicUser
  chatMessages: [ChatMessage!]
  messagesCount: Int
  latestMessage: ChatMessage
}

enum ChatType {
  DYOR_DASHBOARD
}
```

#### `:chat_message`
```graphql
type ChatMessage {
  id: ID!
  content: String!
  role: ChatMessageRole!
  context: JSON
  sources: JSON
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
Lightweight chat representation for list views with messages count, latest message, and type.

### Mutations

#### `sendChatMessage`
```graphql
mutation {
  sendChatMessage(
    chatId: ID          # Optional: creates new chat if not provided
    content: String!    # Required: message content  
    context: {          # Optional: contextual metadata
      dashboardId: String
      asset: String
      metrics: [String]
    }
  ) {
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
  sendChatMessage(
    content: "What are Bitcoin's key metrics?"
    context: {
      asset: "bitcoin"
      metrics: ["price_usd", "volume_usd"]
    }
  ) {
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
  sendChatMessage(
    chatId: "existing-chat-id"
    content: "How about Ethereum?"
    context: {
      asset: "ethereum"
    }
  ) {
    chatMessages {
      content
      role
    }
  }
}
```

### Retrieving Chat History (Authenticated Users)
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

### Anonymous User Examples

#### Creating Anonymous Academy QA Chat
```graphql
mutation {
  sendChatMessage(
    content: "What is DeFi?"
    type: ACADEMY_QA
  ) {
    id  # Save this ID in localStorage for future access
    title
    type
    chatMessages {
      content
      role
      sources  # Academy QA returns structured sources
    }
  }
}
```

#### Continuing Anonymous Conversation
```graphql
mutation {
  sendChatMessage(
    chatId: "saved-chat-id-from-localStorage"
    content: "What are the risks?"
    type: ACADEMY_QA
  ) {
    chatMessages {
      content
      role
      sources
    }
  }
}
```

#### Accessing Anonymous Chat by ID
```graphql
query {
  chat(id: "saved-chat-id-from-localStorage") {
    id
    title
    type
    chatMessages {
      content
      role
      sources
      insertedAt
    }
  }
}
```

## Security & Authorization

### Authenticated Users
- Can access all their own chats via `myChats` query
- Can create, read, update, and delete their own chats
- Cannot access other users' private chats
- Get AI-generated chat titles for better organization

### Anonymous Users
- Can create anonymous chats (user_id = null)
- Can access anonymous chats if they have the chat ID
- Can continue conversations in anonymous chats
- Cannot list chats (no `myChats` access)
- Cannot access authenticated users' private chats
- Do not get AI-generated chat titles (use first message content)

### Access Control Rules
- **Owned chats**: Only the owner can access (user_id matches current_user.id)
- **Anonymous chats**: Anyone can access (user_id is null)
- **Cross-access**: Authenticated users can access anonymous chats; anonymous users cannot access private chats
- Access control enforced at resolver level with `can_access_chat?/2` helper
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

### Sources Support
- Academy QA chat type returns structured sources alongside AI responses
- Sources field contains array of maps with title, URL, similarity, and other metadata
- Sources are stored separately from assistant response content for frontend flexibility
- Available through GraphQL API as JSON field on ChatMessage type

### Academy API Integration
- Academy QA chats integrate with aiserver API at `/academy/query` endpoint
- API receives: question, chat_id, message_id, chat_history (up to 20 messages), user_id
- chat_id: UUID of the chat conversation for context tracking
- message_id: UUID of the specific user message being processed
- user_id: User ID or "anonymous" for unauthenticated users
- API returns structured response with answer text and sources array

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

## Chat Types

The system supports different chat types to distinguish conversations across different UI contexts:

### Current Types
- **"dyor_dashboard"** - Default type for DYOR (Do Your Own Research) dashboard conversations
- **"academy_qa"** - Academy QA conversations with structured source references

### Type Behavior
- All chats default to "dyor_dashboard" type when not specified
- Type is validated at the schema level to ensure only supported types are used
- GraphQL API exposes type as an enum (`DYOR_DASHBOARD`) for type safety
- Internal storage uses strings for simplicity
- Future types can be easily added by updating the `@chat_types` list in the schema

### Adding New Types
To add a new chat type:
1. Add the string value to `@chat_types` in `Sanbase.Chat.Chat`
2. Add the corresponding enum value in `SanbaseWeb.Graphql.ChatTypes` 
3. Update the GraphQL type resolver to handle the new string value
4. Add AI response handling in `maybe_generate_ai_response/5` in ChatResolver
5. Update any relevant documentation

Example of ACADEMY_QA type implementation:
- Added "academy_qa" to schema validation
- Added `:academy_qa` GraphQL enum value  
- Integrated with `AcademyAIService` for specialized responses
- Returns structured sources alongside AI responses 