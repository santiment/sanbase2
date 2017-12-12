import React from 'react'
import {
  Route,
  Switch
} from 'react-router-dom'
import withSizes from 'react-sizes'
import { compose } from 'recompose'
import './App.css'
import Login from './Login'
import Cashflow from './pages/Cashflow'
import Roadmap from './pages/Roadmap'
import Signals from './pages/Signals'
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
        <Route exact path='/cashflow' component={Cashflow} />
        <Route exact path='/roadmap' component={Roadmap} />
        <Route exact path='/signals' component={Signals} />
        <Route path={'/login'} component={Login} />
        <Route exact path={'/'} component={Cashflow} />
      </Switch>
    </ErrorBoundary>
  </div>
)

const mapSizesToProps = ({ width }) => ({
  isDesktop: width > 620
})

const enchance = compose(
  withSizes(mapSizesToProps),
  withTracker
)

export default enchance(App)
