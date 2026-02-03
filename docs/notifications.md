# App Notifications Documentation

This document describes all notification types emitted by the `AppNotificationsSubscriber` module. These notifications are sent to users via WebSocket and can be queried through the GraphQL API.

## Notification Structure

All notifications share the following base structure:

- `id` (integer): Unique notification identifier
- `type` (string): The notification type (see below)
- `entity_type` (string): Type of entity the notification relates to (e.g., "insight", "watchlist", "user_trigger")
- `entity_id` (integer): ID of the entity the notification relates to
- `entity_name` (string): Name/title of the entity
- `user_id` (integer): ID of the user who triggered the notification (the actor, not the receiver)
- `is_broadcast` (boolean): Always `false` for these notifications
- `is_system_generated` (boolean): Always `false` for these notifications
- `json_data` (object): Additional custom data (may be empty `{}`)
- `inserted_at` (datetime): When the notification was created
- `read_at` (datetime | null): When the notification was read by the user (virtual field)

## Notification Types

### 1. `publish_insight`

**Description:** Sent to all followers when a user publishes a new insight.

**Trigger:** When an insight is published (`event_type: :publish_insight`)

**Recipients:** All followers of the insight author

**Standard Fields:**
- `type`: `"publish_insight"`
- `entity_type`: `"insight"`
- `entity_id`: The insight ID
- `entity_name`: The insight title
- `user_id`: The insight author's user ID

**json_data:** `{}` (empty)

**Example:**
```json
{
  "id": 123,
  "type": "publish_insight",
  "entity_type": "insight",
  "entity_id": 456,
  "entity_name": "Bitcoin Price Analysis",
  "user_id": 789,
  "is_broadcast": false,
  "is_system_generated": false,
  "json_data": {},
  "inserted_at": "2026-02-03T10:30:00Z",
  "read_at": null
}
```

---

### 2. `create_watchlist`

**Description:** Sent to all followers when a user creates a new public watchlist.

**Trigger:** When a public watchlist is created (`event_type: :create_watchlist`)

**Recipients:** All followers of the watchlist creator

**Note:** Only public watchlists generate notifications. Private watchlists do not trigger notifications.

**Standard Fields:**
- `type`: `"create_watchlist"`
- `entity_type`: `"watchlist"`
- `entity_id`: The watchlist ID
- `entity_name`: The watchlist name
- `user_id`: The watchlist creator's user ID

**json_data:** `{}` (empty)

**Example:**
```json
{
  "id": 124,
  "type": "create_watchlist",
  "entity_type": "watchlist",
  "entity_id": 101,
  "entity_name": "My DeFi Portfolio",
  "user_id": 789,
  "is_broadcast": false,
  "is_system_generated": false,
  "json_data": {},
  "inserted_at": "2026-02-03T11:00:00Z",
  "read_at": null
}
```

---

### 3. `update_watchlist`

**Description:** Sent to all followers when a user updates a public watchlist.

**Trigger:** When a public watchlist is updated (`event_type: :update_watchlist`)

**Recipients:** All followers of the watchlist owner

**Note:**
- Only public watchlists generate notifications
- Notifications are only sent if there are actual changes to relevant fields that affect the watchlist's content or visibility.
  Changes to the name or description do not trigger notifications.
- There is some cooldown when changing the `is_public` field (2 days). This is to prevent spamming followers with notifications when toggling visibility frequently.

**Standard Fields:**
- `type`: `"update_watchlist"`
- `entity_type`: `"watchlist"`
- `entity_id`: The watchlist ID
- `entity_name`: The watchlist name
- `user_id`: The watchlist owner's user ID

**json_data:** Contains information about what changed:
```json
{
  "changed_fields": ["is_public", "function", "list_items"],  // Array of strings
  "changes": [  // Optional, only present if list_items were added/removed
    {
      "field": "list_items",
      "change_type": "added" | "removed",  // The type of change
      "changes_count": 5  // Number of items added/removed
    }
  ]
}
```

**Possible `changed_fields` values:**
- `"is_public"`: The watchlist visibility changed
- `"function"`: The watchlist function/query changed
- `"list_items"`: Items were added or removed from the watchlist

**Example:**
```json
{
  "id": 125,
  "type": "update_watchlist",
  "entity_type": "watchlist",
  "entity_id": 101,
  "entity_name": "My DeFi Portfolio",
  "user_id": 789,
  "is_broadcast": false,
  "is_system_generated": false,
  "json_data": {
    "changed_fields": ["list_items"],
    "changes": [
      {
        "field": "list_items",
        "change_type": "added",
        "changes_count": 3
      }
    ]
  },
  "inserted_at": "2026-02-03T11:30:00Z",
  "read_at": null
}
```

---

### 4. `create_comment`

**Description:** Sent to the owner of an entity when someone else comments on their entity.

**Trigger:** When a comment is created (`event_type: :create_comment`)

**Recipients:** The owner of the entity being commented on,

**Note:** The comment author does not receive a notification if they comment on their own entity.

**Standard Fields:**
- `type`: `"create_comment"`
- `entity_type`: The type of entity being commented on (e.g., `"insight"`, `"watchlist"`, `"chart"`)
- `entity_id`: The ID of the entity being commented on
- `entity_name`: The name/title of the entity
- `user_id`: The comment author's user ID

**json_data:**
```json
{
  "comment_preview": "This is the first 150 characters of the comment content..."
}
```

**Example:**
```json
{
  "id": 126,
  "type": "create_comment",
  "entity_type": "insight",
  "entity_id": 456,
  "entity_name": "Bitcoin Price Analysis",
  "user_id": 999,
  "is_broadcast": false,
  "is_system_generated": false,
  "json_data": {
    "comment_preview": "Great analysis! I think you're right about the trend..."
  },
  "inserted_at": "2026-02-03T12:00:00Z",
  "read_at": null
}
```

---

### 5. `create_vote`

**Description:** Sent to the owner of an entity when someone else votes on their entity.

**Trigger:** When a vote is created (`event_type: :create_vote`)

**Recipients:** The owner of the entity being voted on

**Notes:**
- The voter does not receive a notification if they vote on their own entity
- There is a 5-minute cooldown period: if the same user votes on the same entity within 5 minutes, only one notification is sent

**Standard Fields:**
- `type`: `"create_vote"`
- `entity_type`: The type of entity being voted on (e.g., `"insight"`, `"watchlist"`, `"chart"`)
- `entity_id`: The ID of the entity being voted on
- `entity_name`: The name/title of the entity
- `user_id`: The voter's user ID

**json_data:** `{}` (empty)

**Example:**
```json
{
  "id": 127,
  "type": "create_vote",
  "entity_type": "insight",
  "entity_id": 456,
  "entity_name": "Bitcoin Price Analysis",
  "user_id": 888,
  "is_broadcast": false,
  "is_system_generated": false,
  "json_data": {},
  "inserted_at": "2026-02-03T12:15:00Z",
  "read_at": null
}
```

---

### 6. `alert_triggered`

**Description:** Sent to a user when one of their alerts is triggered.

**Trigger:** When an alert is triggered (`event_type: :alert_triggered`)

**Recipients:** The owner of the alert (the `user_id` from the event)

**Standard Fields:**
- `type`: `"alert_triggered"`
- `entity_type`: `"user_trigger"`
- `entity_id`: The alert ID
- `entity_name`: The alert title, or `"Alert {alert_id}"` if no title is provided
- `user_id`: The alert owner's user ID

**json_data:** `{}` (empty)

**Example:**
```json
{
  "id": 128,
  "type": "alert_triggered",
  "entity_type": "user_trigger",
  "entity_id": 555,
  "entity_name": "BTC Price Above $50k",
  "user_id": 789,
  "is_broadcast": false,
  "is_system_generated": false,
  "json_data": {},
  "inserted_at": "2026-02-03T13:00:00Z",
  "read_at": null
}
```

