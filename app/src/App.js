import React, { Component } from 'react'
import {
  Route,
  Switch
} from 'react-router-dom'
import './App.css'
import Login from './Login'
import Cashflow from './Cashflow'

class App extends Component {
  render () {
    return (
      <div className='App'>
        <Switch>
          <Route exact path='/cashflow' component={Cashflow} />
          <Route path={'/login'} component={Login} />
          <Route exact path={'/'} component={Cashflow} />
        </Switch>
      </div>
    )
  }
}

export default App
