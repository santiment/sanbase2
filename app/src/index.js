import React from 'react'
import ReactDOM from 'react-dom'
import { BrowserRouter as Router, Route } from 'react-router-dom'
import { Provider } from 'react-redux'
import { createStore, applyMiddleware } from 'redux'
import { composeWithDevTools } from 'redux-devtools-extension'
import axios from 'axios'
import { multiClientMiddleware } from 'redux-axios-middleware'
import App from './App'
import reducers from './reducers/rootReducers.js'
import registerServiceWorker from './registerServiceWorker'
import './index.css'

const clients = {
  sanbaseClient: {
    client: axios.create({
      baseURL: 'http://localhost:4000/api',
      responseType: 'json'
    })
  }
}

const middleware = [multiClientMiddleware(clients)]

const store = createStore(reducers,
  {},
  composeWithDevTools(applyMiddleware(...middleware))
)

ReactDOM.render(
  <Provider store={store}>
    <Router>
      <Route path='/' component={App} />
    </Router>
  </Provider>,
  document.getElementById('root'))
registerServiceWorker()
