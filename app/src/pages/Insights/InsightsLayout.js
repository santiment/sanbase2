import React, { Fragment } from 'react'
import { compose } from 'recompose'
import { connect } from 'react-redux'
import { Helmet } from 'react-helmet'
import { NavLink, Link, withRouter } from 'react-router-dom'
import { Icon, Button } from 'semantic-ui-react'
import Panel from './../../components/Panel'
import './InsightsLayout.css'

const isShowedNewInsightsButton = (history, isLogin) => (
  isLogin &&
  (!history.location.pathname.startsWith('/insights/new') ||
    history.location.pathname === '/insights/newest')
)

const NewInsightBtn = ({history, disabled}) => (
  <Button
    disabled={disabled}
    color='green'
    onClick={() => history.push('/insights/new')}>
    <Icon name='plus' />New insight
  </Button>
)

const InsightsLayout = ({
  isLogin = false,
  title = 'SANbase: Insights',
  sidebar = null,
  loginModalRequest,
  history,
  children,
  hasUsername
}) => (
  <div className='page event-votes insights-page'>
    <Helmet>
      <title>{title}</title>
    </Helmet>
    <div className='insights-page-rows'>
      <div className='insights-page-navs'>
        <h2>Insights</h2>
        <div className='event-votes-navs-list'>
          {isLogin && <NavLink
            to={'/insights/my'}>
            My Insights
          </NavLink>}
          <NavLink
            to={'/insights'}>
            All Insights
          </NavLink>
          <br />
          {isShowedNewInsightsButton(history, isLogin) &&
            <NewInsightBtn
              isLogin={isLogin}
              loginModalRequest={loginModalRequest}
              history={history}
              disabled={!hasUsername}
              />}
        </div>
      </div>
      <div className='insights-page-content'>
        {children}
      </div>
      <div className='insights-page-sidebar'>
        {sidebar && sidebar}
        {!sidebar &&
        <Fragment>
          {isLogin && <div className='insights-page-sidebar-highlights'>
            <div>
              <Link to={'/insights/33'}>How to use Insights: Traders/Investors</Link>
            </div>
            <div>
              <Link to={'/insights/34'}>How to use Insights: Researchers</Link>
            </div>
          </div>}
          <Panel>
            <div className='cta-subscription'>
              <span className=''>Get new signals/insights about crypto in your inbox, every day</span>
              <div id='mc_embed_signup'>
                <form action='//santiment.us14.list-manage.com/subscribe/post?u=122a728fd98df22b204fa533c&amp;id=80b55fcb45' method='post' id='mc-embedded-subscribe-form' name='mc-embedded-subscribe-form' className='validate' target='_blank'>
                  <div id='mc_embed_signup_scroll'>
                    <input type='email' defaultValue='' name='EMAIL' className='email' id='mce-EMAIL' placeholder='Your email address' required />
                    <div className='hidden-xs-up' aria-hidden='true'>
                      <input type='text' name='b_122a728fd98df22b204fa533c_80b55fcb45' tabIndex='-1' value='' />
                    </div>
                    <div className='clear'>
                      <input type='submit' value='Subscribe' name='subscribe' id='mc-embedded-subscribe' className='button' />
                    </div>
                  </div>
                </form>
              </div>
            </div>
          </Panel>
        </Fragment>}
      </div>
    </div>
  </div>
)

const mapStateToProps = state => ({
  hasUsername: !!state.user.data.username
})

const mapDispatchToProps = dispatch => {
  return {
    loginModalRequest: () => {
      dispatch({
        type: 'TOGGLE_LOGIN_REQUEST_MODAL'
      })
    }
  }
}

export default compose(
  connect(mapStateToProps, mapDispatchToProps),
  withRouter
)(InsightsLayout)
