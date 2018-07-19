import React, { Fragment } from 'react'
import { Message } from 'semantic-ui-react'
import { formatCryptoCurrency, formatBTC } from './../utils/formatting'

export const Balance = ({ user, onlyBalance = false }) => {
  return (
    <div>
      {user.ethAccounts && user.ethAccounts.length > 0 ? (
        user.ethAccounts.map((account, index) => (
          <Fragment key={index}>
            {!onlyBalance && (
              <div className='account-name'>
                <a
                  className='address'
                  href={`https://etherscan.io/address/${account.address}`}
                  target='_blank'
                >
                  {account.address}
                </a>
              </div>
            )}
            <div className='account-balance'>
              {formatCryptoCurrency('SAN', formatBTC(account.sanBalance))}
            </div>
          </Fragment>
        ))
      ) : (
        <Message>0 SAN tokens</Message>
      )}
    </div>
  )
}

export default Balance
