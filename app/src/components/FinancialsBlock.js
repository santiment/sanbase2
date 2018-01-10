import React from 'react'
import PropTypes from 'prop-types'
import cx from 'classnames'
import { formatNumber } from '../utils/formatting'
import {
  formatBalanceWallet,
  formatLastOutgoingWallet,
  formatTxOutWallet
} from './../pages/Cashflow'
import './FinancialsBlock.css'

const propTypes = {
  projectTransparencyStatus: PropTypes.string
}

const collectedField = (currency, amount) => {
  if (currency === 'USD') {
    return formatNumber(amount, 'USD')
  }
  return `${currency} ${formatNumber(amount)}`
}

const FinancialsBlock = ({
  projectTransparencyStatus,
  fundsRaisedIcos,
  ethBalance,
  wallets,
  ethPrice
}) => (
  <div>
    Project Transparency:&nbsp;{projectTransparencyStatus || 'Not Listed'}
    <hr />
    <div className={cx({
      'row-info': true,
      'info-disabled': fundsRaisedIcos && fundsRaisedIcos.length === 0
    })}>
      <div>
        Collected
      </div>
      <div className='value'>
        {fundsRaisedIcos.map((amountIco, index) => {
          return <div key={index} >{
            collectedField(amountIco.currencyCode, amountIco.amount)
          }</div>
        })}
      </div>
    </div>
    <div className={cx({
      'row-info': true,
      'info-disabled': !wallets && !ethBalance
    })}>
      <div>
        Balance
      </div>
      {wallets && formatBalanceWallet({wallets, ethPrice})}
    </div>
    <div className={cx({
      'row-info': true,
      'info-disabled': !wallets
    })}>
      <div>Transactions</div>
      <div>
        <div>
          Last outgoing TX: {formatLastOutgoingWallet(wallets)}
        </div>
        <div className='financials-transactions-amount'>
          ETH&nbsp;{formatTxOutWallet(wallets)}
        </div>
      </div>
    </div>
  </div>
)

FinancialsBlock.propTypes = propTypes

export default FinancialsBlock
