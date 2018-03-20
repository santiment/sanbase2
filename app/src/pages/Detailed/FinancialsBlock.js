import React from 'react'
import PropTypes from 'prop-types'
import cx from 'classnames'
import { Label } from 'semantic-ui-react'
import { formatNumber } from '../../utils/formatting'
import { millify } from '../../utils/utils'
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

const showStatus = status => {
  if (status === 'Certified') {
    return (<Label color='green' horizontal>Certified</Label>)
  }
  return status || 'Not Listed'
}

const FinancialsBlock = ({
  projectTransparencyStatus,
  fundsRaisedIcos,
  ethSpent,
  ethBalance,
  btcBalance,
  isERC20
}) => (
  <div>
    Project Transparency:&nbsp;{showStatus(projectTransparencyStatus)}
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
      'info-disabled': !isERC20 || !ethBalance
    })}>
      <div>
        Balance
      </div>
      {ethBalance && `ETH ${millify(parseFloat(parseFloat(ethBalance).toFixed(2)))}`}
    </div>
    <div className={cx({
      'row-info': true,
      'info-disabled': !isERC20 || !ethBalance
    })}>
      <div>ETH Spent 30d</div>
      <div style={{textAlign: 'right'}}>
        {ethSpent ? `ETH ${millify(parseFloat(parseFloat(ethSpent).toFixed(2)))}` : 0}
      </div>
    </div>
  </div>
)

FinancialsBlock.propTypes = propTypes

export default FinancialsBlock
