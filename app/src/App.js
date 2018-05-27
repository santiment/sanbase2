import React from 'react'
import {
  Route as BasicRoute,
  Switch,
  Redirect
} from 'react-router-dom'
import Loadable from 'react-loadable'
import withSizes from 'react-sizes'
import { connect } from 'react-redux'
import { compose } from 'recompose'
import nprogress from 'nprogress'
import 'nprogress/nprogress.css'
import Notification from './components/Notification'
import LoginPage from './pages/Login/LoginPage'
import Cashflow from './pages/Cashflow'
import Currencies from './pages/Currencies'
import Favorites from './pages/Favorites'
import CashflowMobile from './pages/CashflowMobile'
import CurrenciesMobile from './pages/CurrenciesMobile'
import Roadmap from './pages/Roadmap'
import Signals from './pages/Signals'
import Account from './pages/Account'
import BuildChallenge from './pages/BuildChallenge'
import EmailLoginVerification from './pages/EmailLoginVerification'
import TopMenu from './components/TopMenu'
import MobileMenu from './components/MobileMenu'
import withTracker from './withTracker'
import ErrorBoundary from './ErrorBoundary'
import PageLoader from './components/PageLoader'
import Status from './pages/Status'
import Footer from './components/Footer'
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

const LoadableInsight = Loadable({
  loader: () => import('./pages/Insights/Insight'),
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

export const App = ({isDesktop, isLoggedIn, isFullscreenMobile}) => (
  <div className='App'>
    {isFullscreenMobile
      ? undefined
      : (isDesktop
        ? <TopMenu />
        : <MobileMenu />)}
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
        <Route exact path='/currencies' render={props => {
          if (isDesktop) {
            return (
              <Currencies
                preload={() => LoadableDetailedPage.preload()}
                {...props} />
            )
          }
          return (
            <CurrenciesMobile {...props} />
          )
        }} />
        <Route exact path='/favorites' render={props => {
          if (isDesktop && isLoggedIn) {
            return (
              <Favorites
                preload={() => LoadableDetailedPage.preload()}
                {...props} />
            )
          }
          return (
            <Redirect from='/favorites' to='/projects' />
          )
        }} />
        <Route exact path='/roadmap' component={Roadmap} />
        <Route exact path='/signals' component={Signals} />
        <Route path='/insights/new' component={LoadableInsightsNew} />
        <Route path='/insights/update/:insightId' component={LoadableInsightsNew} />
        <Route exact path='/insights' component={LoadableInsights} />
        <Route exact path='/insights/newest' component={LoadableInsights} />
        <Route exact path='/insights/popular' component={LoadableInsights} />
        <Route exact path='/insights/my' component={LoadableInsights} />
        <Route exact path='/insights/users/:userId' component={LoadableInsights} />
        <Route exact path='/insights/:insightId' component={LoadableInsight} />
        <Route exact path='/projects/:slug' render={props => (
          <LoadableDetailedPage isDesktop={isDesktop} {...props} />)} />
        <Route exact path='/account' component={Account} />
        <Route exact path='/status' component={Status} />
        <Route exact path='/build' component={BuildChallenge} />
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
    <Notification />
    {isDesktop && <Footer />}
  </div>
)

const mapStateToProps = state => {
  return {
    isLoggedIn: !!state.user.token,
    isFullscreenMobile: state.detailedPageUi.isFullscreenMobile
  }
}

export const mapSizesToProps = ({ width }) => ({
  isDesktop: width > 768
})

const enchance = compose(
  connect(
    mapStateToProps
  ),
  withSizes(mapSizesToProps),
  withTracker
)

export default enchance(App)
