import React, { Fragment } from 'react'
import { Divider } from 'semantic-ui-react'
import Balance from '../../components/Balance'

const AccountWallets = ({ user }) => {
  return (
    <Fragment>
      <h3>Wallets</h3>
      <Divider />
      <Balance user={user} />
    </Fragment>
  )
}

export default AccountWallets
