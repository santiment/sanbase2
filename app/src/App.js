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
import EventVotes from './pages/EventVotes'
import EventVotesNew from './pages/EventVotesNew/EventVotesNew'
import EmailLoginVerification from './pages/EmailLoginVerification'
import TopMenu from './components/TopMenu'
import MobileMenu from './components/MobileMenu'
import withTracker from './withTracker'
import ErrorBoundary from './ErrorBoundary'
import PageLoader from './components/PageLoader'
import './App.css'

const LoadableDetailedPage = Loadable({
  loader: () => import('./pages/Detailed'),
  loading: () => (
    <PageLoader />
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
      ? <TopMenu />
      : <MobileMenu />}
    <ErrorBoundary>
      <Switch>
        <Route exact path='/projects' render={CashflowPage} />
        <Route exact path='/roadmap' component={Roadmap} />
        <Route exact path='/signals' component={Signals} />
        <Route exact path='/events/votes' component={EventVotes} />
        <Route path='/events/votes/new' component={EventVotesNew} />
        <Route exact path='/events/votes/:filter' component={EventVotes} />
        <Redirect from='/events' to='/events/votes' />
        <Route exact path='/projects/:ticker' render={(props) => (
          <LoadableDetailedPage isDesktop={isDesktop} {...props} />)} />
        <Route exact path='/account' component={Account} />
        <Route path='/login' component={Login} />
        <Route exact path='/' render={CashflowPage} />
        <Route
          exact
          path='/email_login'
          component={EmailLoginVerification} />
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
