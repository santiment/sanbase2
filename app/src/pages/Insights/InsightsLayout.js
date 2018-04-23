import React from 'react'
import { Helmet } from 'react-helmet'
import { NavLink } from 'react-router-dom'
import Panel from './../../components/Panel'
import './InsightsLayout.css'

const InsightsLayout = ({isLogin = false, children}) => (
  <div className='page event-votes'>
    <Helmet>
      <title>SANbase: Insights</title>
    </Helmet>
    <div className='event-votes-rows'>
      <div className='event-votes-navs'>
        <h2>Insights</h2>
        {isLogin && <NavLink
          className='event-votes-navigation__add-link'
          to={'/insights/my'}>
          My Insights
        </NavLink>}
      </div>
      {children}
      <div className='event-votes-sidebar'>
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
      </div>
    </div>
  </div>
)

export default InsightsLayout
