import React, { Fragment } from 'react'
import { Input } from 'semantic-ui-react'
import copy from 'copy-to-clipboard'
import './ApiKey.css'

const ApiKey = ({ apikey, isVisible, onVisibilityButtonClick }) => {
  return (
    <Fragment>
      <form className='ApiKey'>
        <Input
          fluid
          input={{ readOnly: true }}
          value={isVisible ? apikey : '•'.repeat(apikey.length)}
          className='ApiKey__input'
        />
        <button
          type='button'
          onClick={() => onVisibilityButtonClick(apikey)}
          className='ApiKey__btn'
        >
          <i className={`icon eye ${isVisible ? 'slash' : ''}`} />
        </button>
        <button
          type='button'
          onClick={() => copy(apikey)}
          className='ApiKey__btn ApiKey__btn_copy'
        >
          <i className='icon copy' />
        </button>
      </form>
    </Fragment>
  )
}

export default ApiKey
