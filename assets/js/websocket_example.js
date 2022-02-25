
// import { Socket } from "phoenix"
let phoenix = require("phoenix")
let socket = new phoenix.Socket("wss://localhost:4000/socket", { params: {} })
socket.connect()

const channel = socket.channel("metrics:price", {})
channel.join()
    .receive('ok', () => { print("HELLO") })
    .receive('error', () => { print("Error") })
    .receive('timeout', () => { print("timeout") })