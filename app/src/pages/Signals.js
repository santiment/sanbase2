import React from 'react'
import { Helmet } from 'react-helmet'
import { getOrigin } from './../utils/utils'
import './Signals.css'

const Signals = () => (
  <div className='page signals'>
    <Helmet>
      <title>SANbase: Signals</title>
      <link rel='canonical' href={`${getOrigin()}/roadmap`} />
    </Helmet>
    <div className='page-head'>
      <h1>Signals</h1>
      <p>SANbase will generate signals when actionable intelligence or events occur in the crypto-markets.</p>
    </div>
    <div className='container'>
      <div className='panel'>
        <div className='signals-form'>
          <h2><span>Join our <strong>SANbase Signals</strong> email list</span> <span>to receive pre-release alpha and beta signals:</span></h2>
          <div id='mc_embed_signup'>
            <form action='//santiment.us14.list-manage.com/subscribe/post?u=122a728fd98df22b204fa533c&amp;id=80b55fcb45' method='post' id='mc-embedded-subscribe-form' name='mc-embedded-subscribe-form' className='validate' target='_blank' noValidate>
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
        <div className='narrow'>
          <h3>Welcome, community! Santiment will be developing signals over the next few months and would love your help evaluating and testing the feature.</h3>
          <p>
            <strong>Get a first glimpse into what SANbase email signals will look like.</strong> A signal's main purpose is to send a notification
            when something potentially important has happened in the crypto-markets.
            Signals will help you distinguish between mere noise (80% of the chatter) and valuable insights into what is going on in the marketplace.
          </p>
          <p>A few examples:</p>
          <ul>
            <li>Team wallet money has hit an exchange</li>
            <li>Whales (long-term holders) moved part of their holdings to an exchange</li>
            <li>Trading volume of a particular asset has exceeded an average by 50%</li>
            <li>Crowd sentiment has reached an extreme (positive or negative)</li>
          </ul>
          <p>
            Today, all signals you'll receive from this list are free. In the future, some signals will remain free
            (like the first one), for others one will need to pay in SANs (like the last one).
            Signals can be general, but will often be related to a specific asset.
            We'll be looking at asset filtering in future revisions.
          </p>
          <br />
          <p>
            <em>
              <strong>One important note:</strong> To start, Santiment will provide an initial set of signals, yet we also
              will encourage the community (market analysts, data scientists, etc) to provide their own signals on the
              platform. We are gathering a unique set of data for the crypto space and will open access to it through our SAN-api.
              Come join us early.
            </em>
          </p>
        </div>
      </div>
    </div>
  </div>
)

export default Signals
