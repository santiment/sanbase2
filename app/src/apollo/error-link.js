import Raven from 'raven-js'
import { onError } from 'apollo-link-error'

const ErrorLink = onError(({graphQLErrors, networkError, operation}) => {
  if (graphQLErrors) {
    if (Array.isArray(graphQLErrors)) {
      graphQLErrors.forEach(({ message, locations, path }) => {
        const errorMessage = `[GraphQL error]:
          Message: ${JSON.stringify(message)},
          Location: ${JSON.stringify(locations)},
          Path: ${JSON.stringify(path)}`
        if (process.env.NODE_ENV === 'development') {
          console.log(errorMessage)
        }
        if (message !== 'unauthorized' && !/Can't fetch/.test(message)) {
          Raven.captureException(errorMessage)
        }
      })
    } else {
      if (process.env.NODE_ENV === 'development') {
        console.log(
          `[GraphQL error]: ${JSON.stringify(graphQLErrors)}`
        )
      }
      Raven.captureException(`[GraphQL error]: ${JSON.stringify(graphQLErrors)}`)
    }
  }

  if (networkError) {
    if (process.env.NODE_ENV === 'development') {
      console.log(networkError)
    }
    Raven.captureException(`[Network error]: ${networkError}`)
  }
})

export default ErrorLink
