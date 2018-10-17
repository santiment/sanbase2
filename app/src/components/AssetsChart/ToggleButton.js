import React from 'react'
import cx from 'classnames'
import { Popup, Icon, Label, Loader, Message } from 'semantic-ui-react'

const ToggleButton = ({
  loading,
  error = false,
  disabled,
  isToggled,
  // this button for premium timeseries
  premium = false,
  // current user has premium
  hasPremium = false,
  toggle,
  children
}) => (
  <div
    className={cx({
      toggleBtn: true,
      activated: isToggled,
      'premium-wall-button': premium,
      disabled: disabled || loading
    })}
    onClick={() => !disabled && !loading && toggle(!isToggled)}
  >
    {!loading &&
      disabled &&
      !error && (
      <Popup
        trigger={<div>{children}</div>}
        content={
          premium && !hasPremium
            ? 'You need to have more than 1000 tokens to see that data.'
            : "We don't have the data for this project."
        }
        inverted
        position='bottom left'
      />
    )}
    {!loading &&
      !!error && (
      <Popup
        trigger={<div>{children}</div>}
        inverted
        content='There was a problem fetching the data. Please, try again or come back later...'
        position='bottom left'
      />
    )}
    {!loading && !disabled && !error && children}
    {loading && <div className='toggleBtn--loading'>{children}</div>}
    {loading && (
      <div className='toggleBtn-loader'>
        <Loader active inverted={isToggled} size='mini' />
      </div>
    )}
  </div>
)

export default ToggleButton
