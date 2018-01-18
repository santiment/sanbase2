import React from 'react'
import {
  Route,
  Switch,
  Redirect
} from 'react-router-dom'
import Loadable from 'react-loadable'
import withSizes from 'react-sizes'
import { compose } from 'recompose'
import Login from './pages/Login'
import Cashflow from './pages/Cashflow'
import Roadmap from './pages/Roadmap'
import Signals from './pages/Signals'
import Account from './pages/Account'
import SideMenu from './components/SideMenu'
import MobileMenu from './components/MobileMenu'
import withTracker from './withTracker'
import ErrorBoundary from './ErrorBoundary'
import './App.css'

const LoadableDetailedPage = Loadable({
  loader: () => import('./pages/Detailed'),
  loading: () => (
    <div className='page detailed'>
      <h2>Loading...</h2>
    </div>
  )
})

const CashflowPage = props => (
  <Cashflow
    preload={() => LoadableDetailedPage.preload()}
    {...props} />
)

export const App = ({isDesktop}) => (
  <div className='App'>
    {isDesktop
      ? <SideMenu />
      : <MobileMenu />}
    <ErrorBoundary>
      <Switch>
        <Route exact path='/projects' render={CashflowPage} />
        <Route exact path='/roadmap' component={Roadmap} />
        <Route exact path='/signals' component={Signals} />
        <Route exact path='/projects/:ticker' render={(props) => (
          <LoadableDetailedPage isDesktop={isDesktop} {...props} />)} />
        <Route exact path='/account' component={Account} />
        <Route path='/login' component={Login} />
        <Route exact path='/' render={CashflowPage} />
        <Redirect from='/' to='/projects' />
      </Switch>
    </ErrorBoundary>
  </div>
)

export const mapSizesToProps = ({ width }) => ({
  isDesktop: width > 768
})

const enchance = compose(
  withSizes(mapSizesToProps),
  withTracker
)

export default enchance(App)
