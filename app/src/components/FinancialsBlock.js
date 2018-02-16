import React from 'react'
import moment from 'moment'
import PropTypes from 'prop-types'
import cx from 'classnames'
import { formatNumber } from '../utils/formatting'
import './FinancialsBlock.css'

const formatDate = date => moment(date).format('YYYY-MM-DD')

const formatLastOutgoingWallet = wallets => {
  return wallets.map((wallet, index) => {
    const lastOutgoing = wallet.last_outgoing !== null
      ? formatDate(wallet.last_outgoing) : 'No recent transfers'
    return (
      <div key={index}>
        { lastOutgoing }
      </div>
    )
  })
}

const formatTxOutWallet = wallets => {
  return wallets.map((wallet, index) => {
    const txOut = wallet.tx_out || '0.00'
    return (
      <div key={index}>
        {formatNumber(txOut)}
      </div>
    )
  })
}

const formatBalanceWallet = ({wallets, ethPrice}) => {
  return wallets.map((wallet, index) => {
    const balance = wallet.balance || 0
    return (
      <div className='wallet' key={index}>
        <div className='usd first'>{formatNumber((balance * ethPrice), 'USD')}</div>
        <div className='eth'>
          <a
            className='address'
            href={'https://etherscan.io/address/' + wallet.address}
            target='_blank'>Ξ{formatNumber(balance)}&nbsp;
            <i className='fa fa-external-link' />
          </a>
        </div>
      </div>
    )
  })
}

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
        {fundsRaisedIcos ? fundsRaisedIcos.map((amountIco, index) => {
          return <div key={index} >{
            collectedField(amountIco.currencyCode, amountIco.amount)
          }</div>
        }) : '-'}
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
      <div style={{textAlign: 'right'}}>
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
