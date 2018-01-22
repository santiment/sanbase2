import React from 'react'

const Username = ({address}) => (
  <div
    type='text'
    className='account-name'>
    <a
      className='address'
      href={`https://etherscan.io/address/${address}`}
      target='_blank'>{address}
    </a>
  </div>
)

export default Username
