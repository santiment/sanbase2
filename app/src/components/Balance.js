import React from 'react'
import { formatNumber } from './../utils/formatting.js'

export const Balance = ({user}) => {
  return (
    <div>{user.ethAccounts.map((account, index) => (
      <div key={index}>
        <div
          type='text'
          className='account-name'>
          {account.address}
        </div>
        <div className='account-balance'>
          {formatNumber(account.sanBalance, 'SAN')}
        </div>
      </div>
    ))}</div>
  )
}

export default Balance
