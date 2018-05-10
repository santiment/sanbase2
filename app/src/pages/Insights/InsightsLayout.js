import React, { Fragment } from 'react'
import { Helmet } from 'react-helmet'
import { NavLink, Link } from 'react-router-dom'
import Panel from './../../components/Panel'
import './InsightsLayout.css'

const InsightsLayout = ({
  isLogin = false,
  title = 'SANbase: Insights',
  sidebar = null,
  children
}) => (
  <div className='page event-votes'>
    <Helmet>
      <title>{title}</title>
    </Helmet>
    <div className='event-votes-rows'>
      <div className='event-votes-navs'>
        <h2>Insights</h2>
        <div className='event-votes-navs-list'>
          {isLogin && <NavLink
            className='event-votes-navigation__add-link'
            to={'/insights/my'}>
            My Insights
          </NavLink>}
          <NavLink
            className='event-votes-navigation__add-link'
            to={'/insights/newest'}>
            All Insights
          </NavLink>
        </div>
      </div>
      <div className='event-votes-content'>
        {children}
      </div>
      <div className='event-votes-sidebar'>
        {sidebar && sidebar}
        {!sidebar &&
        <Fragment>
          {isLogin && <div className='event-votes-sidebar-highlights'>
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

export default InsightsLayout
