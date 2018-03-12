import React from 'react'
import {
  Route as BasicRoute,
  Switch,
  Redirect
} from 'react-router-dom'
import Loadable from 'react-loadable'
import withSizes from 'react-sizes'
import { compose } from 'recompose'
import nprogress from 'nprogress'
import 'nprogress/nprogress.css'
import LoginPage from './pages/Login/LoginPage'
import Cashflow from './pages/Cashflow'
import CashflowMobile from './pages/CashflowMobile'
import Roadmap from './pages/Roadmap'
import Signals from './pages/Signals'
import Account from './pages/Account'
import EmailLoginVerification from './pages/EmailLoginVerification'
import TopMenu from './components/TopMenu'
import MobileMenu from './components/MobileMenu'
import withTracker from './withTracker'
import ErrorBoundary from './ErrorBoundary'
import PageLoader from './components/PageLoader'
import ImageUpload from './components/ImageUpload'
import './App.css'

const LoadableDetailedPage = Loadable({
  loader: () => import('./pages/Detailed/Detailed'),
  loading: () => (
    <PageLoader />
  )
})

const LoadableInsights = Loadable({
  loader: () => import('./pages/EventVotes'),
  loading: () => (
    <PageLoader />
  )
})

const LoadableInsightsNew = Loadable({
  loader: () => import('./pages/EventVotesNew/EventVotesNew'),
  loading: () => (
    <PageLoader />
  )
})

class Route extends React.Component {
  componentWillMount () {
    nprogress.start()
  }

  componentDidMount () {
    nprogress.done()
  }

  render () {
    return (
      <BasicRoute {...this.props} />
    )
  }
}

export const App = ({isDesktop}) => (
  <div className='App'>
    {isDesktop
      ? <TopMenu />
      : <MobileMenu />}
    <ErrorBoundary>
      <Switch>
        <Route exact path='/projects' render={props => {
          if (isDesktop) {
            return (
              <Cashflow
                preload={() => LoadableDetailedPage.preload()}
                {...props} />
            )
          }
          return (
            <CashflowMobile {...props} />
          )
        }} />
        <Route exact path='/roadmap' component={Roadmap} />
        <Route exact path='/signals' component={Signals} />
        <Route exact path='/insights' component={LoadableInsights} />
        <Route exact path='/uploader' component={ImageUpload} />
        <Route path='/insights/new' component={LoadableInsightsNew} />
        <Route exact path='/insights/:filter' component={LoadableInsights} />
        <Route exact path='/projects/:ticker' render={props => (
          <LoadableDetailedPage isDesktop={isDesktop} {...props} />)} />
        <Route exact path='/account' component={Account} />
        <Route path='/email_login' component={EmailLoginVerification} />
        <Route
          exact
          path='/login'
          render={props => (
            <LoginPage
              isDesktop={isDesktop}
              {...props} />
          )}
        />
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
