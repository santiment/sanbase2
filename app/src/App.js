import React from 'react'
import {
  Route,
  Switch
} from 'react-router-dom'
import withSizes from 'react-sizes'
import './App.css'
import Login from './Login'
import Cashflow from './Cashflow'
import Roadmap from './Roadmap'
import Signals from './Signals'
import SideMenu from './SideMenu'

export const App = ({isDesktop}) => (
  <div className='App'>
    {isDesktop && <SideMenu />}
    <Switch>
      <Route exact path='/cashflow' component={Cashflow} />
      <Route exact path='/roadmap' component={Roadmap} />
      <Route exact path='/signals' component={Signals} />
      <Route path={'/login'} component={Login} />
      <Route exact path={'/'} component={Cashflow} />
    </Switch>
  </div>
)

const mapSizesToProps = ({ width }) => ({
  isDesktop: width > 620
})

export default withSizes(mapSizesToProps)(App)
