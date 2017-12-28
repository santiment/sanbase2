import React from 'react'
import {
  Route,
  Switch,
  Redirect
} from 'react-router-dom'
import withSizes from 'react-sizes'
import { compose } from 'recompose'
import './App.css'
import Login from './pages/Login'
import Cashflow from './pages/Cashflow'
import Roadmap from './pages/Roadmap'
import Signals from './pages/Signals'
import Detailed from './pages/Detailed'
import Account from './pages/Account'
import SideMenu from './components/SideMenu'
import MobileMenu from './components/MobileMenu'
import withTracker from './withTracker'
import ErrorBoundary from './ErrorBoundary'

export const App = ({isDesktop}) => (
  <div className='App'>
    {isDesktop
      ? <SideMenu />
      : <MobileMenu />}
    <ErrorBoundary>
      <Switch>
        <Route exact path='/projects' component={Cashflow} />
        <Route exact path='/roadmap' component={Roadmap} />
        <Route exact path='/signals' component={Signals} />
        <Route exact path='/projects/:ticker' component={Detailed} />
        <Route exact path='/account' component={Account} />
        <Route path='/login' component={Login} />
        <Route exact path='/' component={Cashflow} />
        <Redirect from='/' to='/cashflow' />
      </Switch>
    </ErrorBoundary>
  </div>
)

const mapSizesToProps = ({ width }) => ({
  isDesktop: width > 768
})

const enchance = compose(
  withSizes(mapSizesToProps),
  withTracker
)

export default enchance(App)
