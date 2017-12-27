import React from 'react'
import PropTypes from 'prop-types'

const propTypes = {
  projectTransparencyStatus: PropTypes.string,
  marketCapUsd: PropTypes.string
}

const FinancialsBlock = ({
  marketCapUsd,
  projectTransparencyStatus,
  transparencyRecord,
  transactions,
  balance
}) => (
  <div>
    Project Transparency:&nbsp;{projectTransparencyStatus || 'Not Listed'}
    <hr />
    <div className={`row-info ${!marketCapUsd && 'info-disabled'}`}>
      <div>
        Collected
      </div>
      <div className='value'>
        ${marketCapUsd}
      </div>
    </div>
    <div className={`row-info ${!balance && 'info-disabled'}`}>
      <div>
        Balance
      </div>
      <div>
        {balance}
      </div>
    </div>
    <div className={`row-info ${!transactions && 'info-disabled'}`}>
      <div>
        Transactions
      </div>
      <div>
        <a href='#'>
          {transactions}
        </a>
      </div>
    </div>
    <div className={`row-info ${!transparencyRecord && 'info-disabled'}`}>
      <div>
        Transparency Record
      </div>
      <div>
        <a href='#'>
          {transparencyRecord}
        </a>
      </div>
    </div>
  </div>
)

FinancialsBlock.propTypes = propTypes

export default FinancialsBlock
