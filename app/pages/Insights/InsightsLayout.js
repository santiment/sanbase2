import React, { Fragment } from 'react'
import { compose } from 'recompose'
import { connect } from 'react-redux'
import { Helmet } from 'react-helmet'
import { NavLink, Link, withRouter } from 'react-router-dom'
import { Icon, Button } from 'semantic-ui-react'
import './InsightsLayout.css'

const isShowedNewInsightsButton = (history, isLogin) =>
  isLogin &&
  (!history.location.pathname.startsWith('/insights/new') ||
    history.location.pathname === '/insights/newest')

const NewInsightBtn = ({ history, disabled }) => (
  <Button
    className='new-insights-button'
    disabled={disabled}
    basic
    color='green'
    onClick={() => history.push('/insights/new')}
  >
    <Icon name='plus' />
    New insight
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
      <div className='insights-page-content'>{children}</div>
      <div className='insights-page-sidebar'>
        <h2>Insights</h2>
        <div className='insights-page-navs'>
          <NavLink exact to={'/insights'}>
            All
          </NavLink>
          {isLogin && (
            <NavLink exact to={'/insights/my'}>
              Mine
            </NavLink>
          )}
          {isShowedNewInsightsButton(history, isLogin) && (
            <NewInsightBtn
              isLogin={isLogin}
              loginModalRequest={loginModalRequest}
              history={history}
              disabled={!hasUsername}
            />
          )}
        </div>
        {sidebar && sidebar}
        {!sidebar && (
          <Fragment>
            {isLogin && (
              <div className='insights-page-sidebar-highlights'>
                <Link to={'/insights/33'}>
                  How to use Insights: Traders/Investors
                </Link>
                <Link to={'/insights/34'}>
                  How to use Insights: Researchers
                </Link>
              </div>
            )}
          </Fragment>
        )}
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
  connect(
    mapStateToProps,
    mapDispatchToProps
  ),
  withRouter
)(InsightsLayout)
