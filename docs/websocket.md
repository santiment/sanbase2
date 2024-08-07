## Sanbase WebSocket APIs

Sanbase Websocket endpoints are built on top of the Phoenix library and make a
heavy use of the Phoenix Channels. This means that once a websocket connection
is established, the user can join multiple channels (topics, rooms) and receive
messages in that topic. Examples for topics are: `users:<current user id>`,
`metrics:price`, `metrics:active_addresses_24h` and so on.

## Connecting a socket

Websocket connections can be established both by anonymous and logged-in users.
Anonymous users have access to fewer channels and capabilities. To establish an
authenticated connection, the user must provide either their JWT Access Token
(as obtained in the login mutation) or their Refresh Token's JTI (obtained at
any time via the [getAuthSessions
API](https://api.santiment.net/graphiql?query=%7B%0A%20%20getAuthSessions%20%7B%0A%20%20%20%20jti%0A%20%20%20%20isCurrent%0A%20%20%7D%0A%7D%0A)).
Anonymous websockets are established by providing no arguments

When used in production, it is easier to use the JTI. When used for writing
backend tests, the access token is easier to access.

In Javascript the way to use the websocket API is by using the Phoenix JS
library https://hexdocs.pm/phoenix/js/index.html

A socket initialization looks like this:
```js
import { Socket } from "phoenix"

function logger(kind, msg, data) {
    console.log(`${kind}: ${msg}`, data)
}

let socket = new Socket("wss://api.santiment.net/socket", { params: { jti: "your-jti-goes-here" }, logger: logger})
socket.connect()
socket.onError( () => console.log("there was an error with the connection!") )
socket.onClose( () => console.log("the connection dropped") )
```

```js
let anonSocket = new Socket("wss://api.santiment.net/socket", { params: {}})
```

For Elixir backend testing purposes you can look at the
`./test/sanbase_web/channels` directory where multiple test files are located.

## Joining channels

In all of the following examples, unless it's clearly stated otherwise, the
channels are not accessible to anonymous users.

When a user connects to a socket, an Elixir process is created on the backend
that handles the connection and a special struct called `socket` is used to
identify the connection. In that socket the user details (none, if anonymous)
are stored and are used when the user tries to join channels over the websocket
connection.

The channel joining looks like this for a user with id 1:
```js
const channel = socket.channel("metrics:price", {})
channel.join()
    .receive('ok', () => { console.log("Success") })
    .receive('error', () => { console.log("Error") })
    .receive('timeout', () => { console.log("Timeout") })
```

The separation with `:` is only for clarity and the whole string is the one
representing the topic.

Users can send messages to a channel and receive messages from a channel.

### The `users:common` channel

Both authenticated and anonymous users can join this channel.

In this channel there are two messages that users can send:

#### `is_username_valid` to check if a username is free and valid to use

A username is valid if it's not taken and it fulfills a set of requirements,
that include, but are not limited to:
- The username is not too short
- The username does not contain profanities
- The username is not already taken

```js
const channel = socket.channel(`users:common`, {})
channel.join()
    .receive('ok', () => { console.log("Success") })
    .receive('error', () => { console.log("Error") })
    .receive('timeout', () => { console.log("Timeout") })

channel
    .push('is_username_valid', {username: "ivan"}, PUSH_TIMEOUT)
    .receive('ok', ({ is_username_valid, reason }) => {
        if(is_username_valid === true){
            console.log('Username is valid')
        } else {
            console.log(`Username not valid. Reason: ${reason}`)
        }
    })
```

#### `users_by_username_pattern` - search users by providing a username pattern

Returns list of users (user, username, id, avatarUrl) that match the provided
username pattern. By default, the search is done by returning all users that
contain the provided pattern in their username. If only prefix/suffix matching
is done, this can be controlled by changing the search pattern like this:
`pattern%` (search prefix) or `%pattern` (search suffix).

The `size` argument controls how many results should be returned. The `size`
number of closest usernames are returned. Closeness is measured with [Jaro
distance](https://en.wikipedia.org/wiki/Jaro%E2%80%93Winkler_distance).

```js
const channel = socket.channel(`users:common`, {})
channel.join()
    .receive('ok', () => { console.log("Success") })
    .receive('error', () => { console.log("Error") })
    .receive('timeout', () => { console.log("Timeout") })

channel
    .push('users_by_username_pattern', {username_pattern: "ivan", size: 10}, PUSH_TIMEOUT)
    .receive('ok', ({users}) => {
       for (let {username, id, name, avatarUrl} of users){
         console.log(`id: ${id}, username: ${username}, name: ${name}, avatarUrl: ${avatarUrl}`)
       }
    })
```

### The `users:<user id>` channels

Users can join the channel `users:<current user id>`. The join is successful
only if the user uses their id. If the JTI used when establishing the connection
has id 1, then this websocket can be used only to join the channel `users:1` and
not `users:2`, `users:3`.
No messages are supported in this channal yet.


### The `open_restricted_tabs:*` channels

This channel is joined from the frontend when the user opens part of sanbase
that is part of the restricted sections. In this channel there is one message
that users can send that check what is the number of open restricted tabs.
```js
const channel = socket.channel(`open_restricted_tabs:${user.id}`, {})
channel.join()
    .receive('ok', () => { console.log("Success") })
    .receive('error', () => { console.log("Error") })
    .receive('timeout', () => { console.log("Timeout") })

channel
    .push('open_restricted_tabs', {}, PUSH_TIMEOUT)
    .receive('ok', ({ open_restricted_tabs }) => {
        console.log(`Currently restricted tabs open are ${open_restricted_tabds}`)
    })
```

