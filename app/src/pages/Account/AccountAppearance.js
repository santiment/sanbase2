import React, { Fragment } from 'react'
import { Divider, Checkbox } from 'semantic-ui-react'

const AccountAppearance = ({ onNightModeToggleChange, isNightModeEnabled }) => {
  return (
    <Fragment>
      <h3>Appearance</h3>
      <Divider />
      <div className='account-control account-control-appearance'>
        <p>Night Mode</p>
        <Checkbox toggle onChange={onNightModeToggleChange} defaultChecked={isNightModeEnabled} />
      </div>
    </Fragment>
  )
}

export default AccountAppearance
