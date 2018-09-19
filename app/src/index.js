import React from 'react'
import ReactDOM from 'react-dom'
import { Route } from 'react-router-dom'
import { Provider } from 'react-redux'
import { createStore, applyMiddleware } from 'redux'
import { createEpicMiddleware } from 'redux-observable'
import { composeWithDevTools } from 'redux-devtools-extension'
import createRavenMiddleware from 'raven-for-redux'
import throttle from 'lodash.throttle'
import ApolloClient from 'apollo-client'
import { createHttpLink } from 'apollo-link-http'
import { from } from 'apollo-link'
import { InMemoryCache } from 'apollo-cache-inmemory'
import { ApolloProvider } from 'react-apollo'
import createHistory from 'history/createBrowserHistory'
import { ConnectedRouter, routerMiddleware } from 'react-router-redux'
import App from './App'
import reducers from './reducers/rootReducers.js'
import epics from './epics/rootEpics.js'
import { loadState, saveState } from './utils/localStorage'
import { getAPIUrl } from './utils/utils'
import detectNetwork from './utils/detectNetwork'
import getRaven from './utils/getRaven'
import { changeNetworkStatus, launchApp } from './actions/rootActions'
import uploadLink from './apollo/upload-link'
import errorLink from './apollo/error-link'
import authLink from './apollo/auth-link'
import retryLink from './apollo/retry-link'
import { unregister } from './serviceWorker'
import 'semantic-ui-css/semantic.min.css'
import './index.css'

const main = () => {
  const httpLink = createHttpLink({ uri: `${getAPIUrl()}/graphql` })
  const client = new ApolloClient({
    link: from([authLink, errorLink, retryLink, uploadLink, httpLink]),
    shouldBatch: true,
    cache: new InMemoryCache()
  })

  const history = createHistory()

  const middleware = [
    createEpicMiddleware(epics, {
      dependencies: {
        client
      }
    }),
    routerMiddleware(history),
    createRavenMiddleware(getRaven())
  ]

  const store = createStore(
    reducers,
    { user: loadState() } || {},
    composeWithDevTools(applyMiddleware(...middleware))
  )

  store.subscribe(
    throttle(() => {
      saveState(store.getState().user)
    }, 1000)
  )

  store.dispatch(launchApp())

  detectNetwork(({ online = true }) => {
    store.dispatch(changeNetworkStatus(online))
  })

  unregister()

  ReactDOM.render(
    <ApolloProvider client={client}>
      <Provider store={store}>
        <ConnectedRouter history={history}>
          <Route path='/' component={App} />
        </ConnectedRouter>
      </Provider>
    </ApolloProvider>,
    document.getElementById('root')
  )
}

if (process.env.NODE_ENV === 'development') {
  const { whyDidYouUpdate } = require('why-did-you-update')
  if (process.env.REACT_APP_DEBUG) {
    whyDidYouUpdate(React)
  }
  main()
} else {
  const script = document.createElement('script')
  script.src = `/env.js?${process.env.REACT_APP_VERSION}`
  script.async = false
  document.body.appendChild(script)
  script.addEventListener('load', main)
}
