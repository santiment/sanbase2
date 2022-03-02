# Sanbase WebSocket APIs

Sanbase Websocket endpoints are built on top of the Phoenix library and make a
heavy use of the Phoenix Channels. This means that once a websocket connection
is established, the user can join multiple channels (topics, rooms) and receive
messages in that topic. Examples for topics are: `users:<current user id>`,
`metrics:price`, `metrics:active_addresses_24h` and so on.

## Connecting a socket

At the time of writing this, websocket connections can be established only by
logged-in users. To establish a connection, the user must provide either their
JWT Access Token (as obtained in the login mutation) or their Refresh Token's
JTI (obtained at any time via the [getAuthSessions
API](https://api.santiment.net/graphiql?query=%7B%0A%20%20getAuthSessions%20%7B%0A%20%20%20%20jti%0A%20%20%20%20isCurrent%0A%20%20%7D%0A%7D%0A))

When used in production, it is easier to use the JTI. When used for writing backend tests, the access token is easier to access.

In Javascript the way to use the websocket API is by using the Phoenix JS library https://hexdocs.pm/phoenix/js/index.html

A socket initialization looks like this:
```js
import { Socket } from "phoenix"

function logger(kind, msg, data) {
    console.log(`${kind}: ${msg}`, data)
}

let socket = new Socket("wss://api.santiment.net/socket", { params: { jti: "your-jti-goes-here" }})
socket.connect()
socket.onError( () => console.log("there was an error with the connection!") )
socket.onClose( () => console.log("the connection dropped") )
```

For Elixir backend testing purposes you can look at the `./test/sanbase_web/channels` directory where multiple test files are located.

## Joining channels

When a user connects to a socket, an Elixir process is created on the backend that handles the connection and a special struct called `socket` is used to identify the connection.
In that socket the user details are stored and are used when the user tries to join channels over the websocket connection.

The channel joining looks like this for a user with id 1:
```js
const channel = socket.channel("metrics:price", {})
channel.join()
    .receive('ok', () => { console.log("Success") })
    .receive('error', () => { console.log("Error") })
    .receive('timeout', () => { console.log("Timeout") })
```

The separation with `:` is only for clarity and the whole string is the one representing the topic.

Users can send messages to a channel and receive messages from a channel.

### The `users:*` channels

Users can join the channel `users:<current user id>`. The join is successful only if the user uses their id. If the JTI used when establishing the connection has id 1, then this websocket can be used only to join the channel `users:1` and not `users:2`, `users:3`, etc.

In this channel there is one message that users can send that check is a username is valid and free.
```js
const channel = socket.channel(`users:${user.id}`, {}).join()

channel
    .push('is_username_valid', {username: "ivan"}, PUSH_TIMEOUT)
    .receive('ok', ({ is_username_valid, reason }) => {
        if is_username_valid === true {
            console.log('Username is valid')
        } else {
            console.log(`Username not valid. Reason: ${reason}`)
        }
    })
```

### The `open_restricted_tabs:*` channels

This channel is joined from the frontend when the user opens part of sanbase that is part of the restricted sections.
In this channel there is one message that users can send that check what is the number of open restricted tabs.
```js
const channel = socket.channel(`open_restricted_tabs:${user.id}`, {}).join()

channel
    .push('open_restricted_tabs', {}, PUSH_TIMEOUT)
    .receive('ok', ({ open_restricted_tabs }) => {
        console.log(`Currently restricted tabs open are ${open_restricted_tabds}`)
    })
```

### The `metrics:*` channels

The metrics channels are used to receive newly computed metrics without asking for them.
Users can use subtopics like `price`, `all` or a specific metric like `active_addresses_24h`.
When the channel is joined, the user will automatically start receiving all the new data points
that appear in our databases withou making request for that.

```js
const channel = socket.channel(`metrics:price`, {}).join()

channel.on('metric_data', ({metric, slug, datetime, value}) => {
    console.log(`Received new metric: ${datetime}, ${metric}, ${slug}, ${value}`)
})
```

The channel has two optional arguments - `slugs` and `metrics`. This way you can control and receive
only data only for some of the slugs and the metrics:
```js
const channel = socket.channel(`metrics:price`, {metrics: ['price_usd', 'price_btc'], slugs: ['bitcoin', 'ethereum']}).join()
```

By default, if no arguments are provided, all metrics, slugs and sources are streamed to the user.

The slugs/metrics can be added/removed after the channel is joined with the messages:
- `subscribe_slugs`/`unsubscribe_slugs`
- `subscribe_metrics`/`unsubscribe_metrics`
- `subscribe_sources`/`unsubscribe_sources`


```js
channel.push('subscribe_slugs', {slugs: ['bitcoin', 'ethereum']}, 10000)
channel.push('subscribe_metrics', {metrics: ['price_usd', 'price_btc']}, 10000)
channel.push('subscribe_metrics', {metrics: ['price_usd', 'price_btc']}, 10000)
```