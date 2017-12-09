import React, { Fragment } from 'react'
import { Divider } from 'semantic-ui-react'
import Balance from '../../components/Balance'

const AccountWallets = ({ user }) => (
  <Fragment>
    <h3 id='balance'>Wallets</h3>
    <Divider />
    <Balance user={user} />
    <hr />
    <div>
      <h5>GET SAN AT</h5>
      <ul>
        <li>
          <a
            href='https://www.bitfinex.com/'
            rel='noopener noreferrer'
            target='_blank'
          >
            Bitfinex
          </a>
        </li>
        <li>
          <a
            href='https://liqui.io/#/exchange/SAN_ETH'
            rel='noopener noreferrer'
            target='_blank'
          >
            Liqui
          </a>
        </li>
        <li>
          <a
            href='https://www.okex.com/'
            rel='noopener noreferrer'
            J
            target='_blank'
          >
            OKeX
          </a>
        </li>
        <li>
          <a
            href='https://hitbtc.com/'
            rel='noopener noreferrer'
            J
            target='_blank'
          >
            HitBTC
          </a>
        </li>
      </ul>
    </div>
  </Fragment>
)

export default AccountWallets
