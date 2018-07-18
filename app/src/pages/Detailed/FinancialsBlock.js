import React from 'react'
import PropTypes from 'prop-types'
import cx from 'classnames'
import { Label } from 'semantic-ui-react'
import {
  formatCryptoCurrency,
  formatNumber,
  millify
} from './../../utils/formatting'
import './FinancialsBlock.css'

const propTypes = {
  projectTransparencyStatus: PropTypes.string
}

export const collectedField = (currency, amount) => {
  if (currency === 'USD') {
    return formatNumber(amount, { currency: 'USD' })
  }
  return formatCryptoCurrency(currency, formatNumber(amount))
}

const showStatus = status => {
  if (status === 'Certified') {
    return (
      <Label color='green' horizontal>
        Certified
      </Label>
    )
  }
  return status || 'Not Listed'
}

const FinancialsBlock = ({
  projectTransparencyStatus,
  fundsRaisedIcos,
  ethSpent,
  ethBalance,
  btcBalance,
  ethAddresses,
  isERC20
}) => (
  <div>
    Project Transparency:&nbsp;{isERC20
      ? showStatus(projectTransparencyStatus)
      : 'Not applicable'}
    <hr />
    {fundsRaisedIcos &&
      fundsRaisedIcos.length !== 0 && (
        <div className='row-info'>
          <div>Collected</div>
          <div className='value'>
            {fundsRaisedIcos
              ? fundsRaisedIcos.map((amountIco, index) => {
                return (
                  <div key={index}>
                    {collectedField(amountIco.currencyCode, amountIco.amount)}
                  </div>
                )
              })
              : '-'}
          </div>
        </div>
      )}
    {ethBalance && (
      <div
        className={cx({
          'row-info wallets': true,
          'info-disabled': !isERC20 || !ethBalance
        })}
      >
        <div>Wallet Balances</div>
      </div>
    )}
    {isERC20 && (
      <div className='row-info wallets-balance'>
        {ethAddresses.map((wallet, index) => (
          <div key={index}>
            <div className='wallets-addresses'>
              <a href={`https://etherscan.io/address/${wallet.address}`}>
                {wallet.address}
              </a>
              <span>ETH {millify(wallet.balance, 2)}</span>
            </div>
          </div>
        ))}
      </div>
    )}
    {ethBalance && (
      <div
        className={cx({
          'row-info': true,
          'info-disabled': !isERC20 || !ethBalance
        })}
      >
        <div>Total Balance</div>
        {ethBalance && `ETH ${millify(ethBalance, 2)}`}
      </div>
    )}
    {isERC20 && (
      <div
        className={cx({
          'row-info': true,
          'info-disabled': !isERC20 || !ethBalance
        })}
      >
        <div>ETH Spent 30d</div>
        <div style={{ textAlign: 'right' }}>
          {ethSpent ? `ETH ${millify(ethSpent, 2)}` : 0}
        </div>
      </div>
    )}
  </div>
)

FinancialsBlock.propTypes = propTypes

export default FinancialsBlock
