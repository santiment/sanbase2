import React from 'react'
import { pure } from 'recompose'
import HelpPopup from './../../components/HelpPopup/HelpPopup'
import './PricingHelpMessage.css'

const PricingHelpMessage = (isPremium = false) => {
  if (!isPremium) {
    return ''
  }
  return (
    <div className='pricing-details'>
      <label className='pricing-details__label'>Limited data.</label>
      &nbsp;Unlock the full app. &nbsp;<HelpPopup
        trigger={<span>Learn more</span>}
      >
        <div>
          <p>
            <strong>We are free now for general usage.</strong>
          </p>
          <p>
            <strong>SANbase:</strong> 1000 SAN tokens staking
          </p>
          <ul>
            <li>Historical data more than 3 month</li>
            <li>Social: Project sentiment feed</li>
            <li>Insights voting</li>
          </ul>
          <p>
            <strong>API:</strong> 1000 SAN tokens staking
          </p>
          <ul>
            <li>Realtime data</li>
          </ul>
          <hr />
          <strong>How do I stake SAN?</strong>
          <ul>
            <li>Get Metamask and create an ETH address</li>
            <li>
              Obtain $SAN tokens from any of the exchanges listed here:
              https://coinmarketcap.com/currencies/santiment/#markets
            </li>
            <li>
              Transfer $SAN tokens from exchange to your Metamask ETH address.
              Note: Be sure to have required amount of SAN for access.
            </li>
            <li>Sign in to desired platform with Metamask for access.</li>
          </ul>
        </div>
      </HelpPopup>
    </div>
  )
}

export default pure(PricingHelpMessage)
