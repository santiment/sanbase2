import React, { Fragment } from 'react'
import { Helmet } from 'react-helmet'

const AccountHeader = () => {
  return (
    <Fragment>
      <Helmet>
        <title>
          SANbase: Settings
        </title>
      </Helmet>
      <div className='page-head'>
        <h1>Account settings</h1>
      </div>
    </Fragment>
  )
}

export default AccountHeader
