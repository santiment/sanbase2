import React from 'react'
import PropTypes from 'prop-types'

const propTypes = {
  info: PropTypes.object.isRequired
}

const FinancialsBlock = ({info}) => (
  <div>
    Project Transparency: NOT LISTED
    <hr />
    <div className='row-info'>
      <div>
        Collected
      </div>
      <div className='value'>
        ${info.market_cap_usd}
        <br />
        (2017-05-17)
      </div>
    </div>
    <div className='row-info'>
      <div>
        Balance
      </div>
      <div>
        $57,345,121
        <br />
        (Ξ266,698.0)
      </div>
    </div>
    <div className='row-info'>
      <div>
        Transactions
      </div>
      <div>
        <a href='#'>
          0xcafE1A77e84698c83CA8931F54A755176eF75f2C
        </a>
      </div>
    </div>
    <div className='row-info'>
      <div>
        Transparency Record
      </div>
      <div>
        <a href='#'>
          http://transparency.aragon.one
        </a>
      </div>
    </div>
  </div>
)

FinancialsBlock.propTypes = propTypes

export default FinancialsBlock
