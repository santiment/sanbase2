<a href="http://localhost:4000/apiexplorer?variables=%7B%7D&query=query%20%7B%0A%20%20githubActivity(%0A%20%20%20%20ticker:%20%22SAN%22,%0A%20%20%20%20from:%20%222017-05-13%2015:00:00Z%22,%0A%20%20%20%20interval:%20%2224h%22)%20%7B%0A%20%20%20%20%20%20activity%0A%20%20%20%20%7D%0A%7D%0A" target='_blank' >Run in explorer</a>

```graphql
query {
  githubActivity(
    ticker: "SAN",
    from: "2017-05-13 15:00:00Z",
    interval: "24h") {
      activity
    }
}
```
