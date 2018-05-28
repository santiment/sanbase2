import React from 'react'
import ReactDOM from 'react-dom'
import { BrowserRouter as Router, Route } from 'react-router-dom'
import { Provider } from 'react-redux'
import { createStore, applyMiddleware } from 'redux'
import { createEpicMiddleware } from 'redux-observable'
import { composeWithDevTools } from 'redux-devtools-extension'
import axios from 'axios'
import { multiClientMiddleware } from 'redux-axios-middleware'
import Raven from 'raven-js'
import createRavenMiddleware from 'raven-for-redux'
import ApolloClient, { printAST } from 'apollo-client'
import gql from 'graphql-tag'
import { createHttpLink } from 'apollo-link-http'
import { setContext } from 'apollo-link-context'
import { from, ApolloLink, Observable } from 'apollo-link'
import { onError } from 'apollo-link-error'
import { InMemoryCache } from 'apollo-cache-inmemory'
import { ApolloProvider } from 'react-apollo'
import App from './App'
import reducers from './reducers/rootReducers.js'
import epics from './epics/rootEpics.js'
import { loadState, saveState } from './utils/localStorage'
import { getOrigin } from './utils/utils'
import setAuthorizationToken from './utils/setAuthorizationToken'
import { hasMetamask } from './web3Helpers'
// Look at 42 line. ;)
// import * as serviceWorker from './serviceWorker'

import 'semantic-ui-css/semantic.min.css'
import './index.css'

const run = (client, store, App) => {
  ReactDOM.render(
    <ApolloProvider client={client}>
      <Provider store={store}>
        <Router>
          <Route path='/' component={App} />
        </Router>
      </Provider>
    </ApolloProvider>,
    document.getElementById('root'))

  // TODO: 2018-04-25 Yura Z.: Need to change deploy logic for frontend
  // Until we don't use s3 for static, we have problem with webworkers,
  // after each updates.
  /* serviceWorker.register({
    onUpdate: registration => {
      console.log('App updated... Refresh your browser, please.')
    },
    onSuccess: registration => {
      console.log('Your browser makes cached SANbase version')
    }
  }) */
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.ready.then(registration => {
      registration.unregister()
    })
  }
}

const handleLoad = () => {
  if (!window.env) {
    window.env = {
      RAVEN_DSN: '',
      WEBSITE_URL: process.env.REACT_APP_WEBSITE_URL || ''
    }
  }
  Raven.config(window.env.RAVEN_DSN || '', {
    release: process.env.REACT_APP_VERSION,
    environment: process.env.NODE_ENV,
    tags: {
      git_commit: process.env.REACT_APP_VERSION.split('-')[1]
    }
  }).install()
  const origin = getOrigin()

  const httpLink = createHttpLink({ uri: `${origin}/graphql` })

  const authLink = setContext((_, { headers }) => {
    // get the authentication token from local storage if it exists
    const token = loadState() ? loadState().token : undefined
    // return the headers to the context so httpLink can read them
    return {
      headers: {
        ...headers,
        authorization: token ? `Bearer ${token}` : null
      }
    }
  })

  const isObject = value => value !== null && typeof value === 'object'

  const uploadLink = new ApolloLink((operation, forward) => {
    if (typeof FormData !== 'undefined' && isObject(operation.variables)) {
      const files = operation.variables.images
      if (files && files.length > 0) {
        const { headers } = operation.getContext()
        const formData = new FormData() // eslint-disable-line

        const filesData = Object.keys(files).filter(key => {
          return files[key].name
        })
        formData.append('query', printAST(operation.query))
        let variables = {'images': []}
        filesData.forEach(key => {
          variables['images'].push(files[key].name)
          formData.append(files[key].name, files[key])
        })
        formData.append('variables', JSON.stringify(variables))

        return new Observable(observer => {
          fetch(`${origin}/graphql`, { // eslint-disable-line
            method: 'POST',
            headers: {
              ...headers
            },
            body: formData
          })
          .then(response => {
            if (!response.ok) {
              throw Error(response.statusText)
            }
            return response.json()
          })
          .then(success => {
            observer.next(success)
            observer.complete()
          }).catch(error => {
            observer.next(error)
            observer.error(error)
          })
        })
      }
    }
    return forward(operation)
  })

  const linkError = onError(({graphQLErrors, networkError, operation}) => {
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
          if (message !== 'unauthorized') {
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

  const client = new ApolloClient({
    link: from([authLink, linkError, uploadLink, httpLink]),
    shouldBatch: true,
    cache: new InMemoryCache()
  })

  const clients = {
    sanbaseClient: {
      client: axios.create({
        baseURL: `${origin}/api`,
        responseType: 'json'
      })
    }
  }

  loadState() && setAuthorizationToken(loadState().token)

  const middleware = [
    multiClientMiddleware(clients),
    createEpicMiddleware(epics, {
      dependencies: {
        client
      }
    }),
    createRavenMiddleware(Raven)
  ]

  const store = createStore(reducers,
    {user: loadState()} || {},
    composeWithDevTools(applyMiddleware(...middleware))
  )

  client.query({
    query: gql`
      query {
        currentUser {
          id,
          email,
          username,
          ethAccounts{
            address,
            sanBalance
          }
        }
      }
    `
  })
  .then(response => {
    if (response.data.currentUser) {
      store.dispatch({
        type: 'CHANGE_USER_DATA',
        user: response.data.currentUser,
        hasMetamask: hasMetamask()
      })
    }
  })
  .catch(error => Raven.captureException(error))

  store.subscribe(() => {
    saveState(store.getState().user)
  })

  if (!window.Intl) {
    require.ensure([
      'intl',
      'intl/locale-data/jsonp/en.js'
    ], () => {
      require('intl')
      require('intl/locale-data/jsonp/en.js')
      run(client, store, App)
    })
  } else {
    run(client, store, App)
  }
}

if (process.env.NODE_ENV === 'development') {
  handleLoad()
} else {
  const script = document.createElement('script')
  script.src = `/env.js?${process.env.REACT_APP_VERSION}`
  script.async = false
  document.body.appendChild(script)
  script.addEventListener('load', handleLoad)
}
