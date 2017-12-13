import React from 'react'
import PropTypes from 'prop-types'
import './FinancialsBlock.css'

const propTypes = {
  info: PropTypes.object.isRequired
}

const FinancialsBlock = ({info}) => (
  <div>
    Project Transparency: NOT LISTED
    <hr />
    <div className='rowInfo'>
      <div>
        Collected
      </div>
      <div>
        ${info.market_cap_usd}
      </div>
    </div>
    <div className='rowInfo'>
      <div>
        Balance
      </div>
      <div>
        $57,345,121
      </div>
    </div>
    <div className='rowInfo'>
      <div>
        Transactions
      </div>
      <div>
        $57,345,121
      </div>
    </div>
    <div className='rowInfo'>
      <div>
        Transparency Record
      </div>
      <div>
        $57,345,121
      </div>
    </div>
  </div>
)

FinancialsBlock.propTypes = propTypes

export default FinancialsBlock
