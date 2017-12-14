import React from 'react'
import PropTypes from 'prop-types'
import './GeneralInfoBlock.css'

const propTypes = {
  info: PropTypes.object.isRequired
}

const GeneralInfoBlock = ({info}) => (
  <div>
    <p className='social-icons'>
      <a href='#'>
        <i className='fa fa-globe' />
      </a>
      <a href='#'>
        <i className='fa fa-slack' />
      </a>
      <a href='#'>
        <i className='fa fa-twitter' />
      </a>
      <a href='#'>
        <i className='fa fa-medium' />
      </a>
      <a href='#'>
        <i className='fa fa-github' />
      </a>
    </p>
    <hr />
    <div className='row-info'>
      <div>
        Market Cap
      </div>
      <div>
        ${info.market_cap_usd}
      </div>
    </div>
    <div className='row-info'>
      <div>
        Volume
      </div>
      <div>
        $57,345,121
        <span className='diff down'>
          <i className='fa fa-caret-down' />
          &nbsp; 8.87%
        </span>
      </div>
    </div>
    <div className='row-info'>
      <div>
        Circulating
      </div>
      <div>
        $57,345,121
      </div>
    </div>
    <div className='row-info'>
      <div>
        Total supply
      </div>
      <div>
        $57,345,121
      </div>
    </div>
    <div className='row-info'>
      <div>
        Rank
      </div>
      <div>
        {info.id}
      </div>
    </div>
    <div className='row-info'>
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
