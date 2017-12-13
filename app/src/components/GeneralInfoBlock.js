import React from 'react'
import PropTypes from 'prop-types'
import './GeneralInfoBlock.css'

const propTypes = {
  info: PropTypes.object.isRequired
}

const GeneralInfoBlock = ({info}) => (
  <div>
    <hr />
    <div className='rowInfo'>
      <div>
        Market Cap
      </div>
      <div>
        ${info.market_cap_usd}
      </div>
    </div>
    <div className='rowInfo'>
      <div>
        Volume
      </div>
      <div>
        $57,345,121
      </div>
    </div>
    <div className='rowInfo'>
      <div>
        Circulating
      </div>
      <div>
        $57,345,121
      </div>
    </div>
    <div className='rowInfo'>
      <div>
        Total supply
      </div>
      <div>
        $57,345,121
      </div>
    </div>
    <div className='rowInfo'>
      <div>
        Rank
      </div>
      <div>
        {info.id}
      </div>
    </div>
    <div className='rowInfo'>
      <div>
        ROI since ICO
      </div>
      <div>
        $57,345,121
      </div>
    </div>
  </div>
)

GeneralInfoBlock.propTypes = propTypes

export default GeneralInfoBlock
