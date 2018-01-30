import React, { Fragment } from 'react'
import { formatNumber } from './../utils/formatting.js'

export const Balance = ({user}) => {
  return (
    <div>{user.ethAccounts.map((account, index) => (
      <Fragment key={index}>
        <div
          type='text'
          className='account-name'>
          <a
            className='address'
            href={`https://etherscan.io/address/${account.address}`}
            target='_blank'>{account.address}
          </a>
        </div>
        <div className='account-balance'>
          {formatNumber(account.sanBalance, 'SAN')}
        </div>
      </Fragment>
    ))}
    </div>
  )
}

export default Balance
