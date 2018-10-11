import React from 'react'
import HelpPopup from './../../components/HelpPopup/HelpPopup'
import './PricingHelpMessage.css'

const PricingHelpMessage = () => (
  <div className='pricing-details'>
    <label className='pricing-details__label'>Limited data.</label>
    &nbsp;Unlock the full app. &nbsp;
    <HelpPopup trigger={<span>Learn more</span>}>
      <div>
        <p>
          <strong>We are free now for general usage.</strong>
        </p>
        <p>
          <strong>Upgrade to access more, including:</strong>
        </p>
        <ul>
          <li>Historical data more than 3 month</li>
          <li>Additional sentiment data</li>
          <li>Insights voting capabilities</li>
          <li>Real-time data (API)</li>
        </ul>
        <hr />
        <strong>How to upgrade?</strong>
        <ul>
          <li>Install the MetaMask add-on</li>
          <li>
            Buy $SAN tokens from an exchange:
            https://coinmarketcap.com/currencies/santiment/#markets a minimum of
            $SAN 1000 is required
          </li>
          <li>
            Transfer $SAN tokens from exchange to MetaMask wallet. Note: Be sure
            to have required amount of SAN for access.
          </li>
        </ul>
      </div>
    </HelpPopup>
  </div>
)

export default PricingHelpMessage
