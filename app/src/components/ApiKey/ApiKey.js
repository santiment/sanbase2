import React, {Fragment} from 'react'
import { Input } from 'semantic-ui-react'
import copy from 'copy-to-clipboard'
import './ApiKey.css'

const ApiKey = ({apikey, isHidden, onVisibilityButtonClick}) => {
  return (
    <Fragment>
      <form className='ApiKey'>
        <Input
          fluid
          input={{ readOnly: true }}
          value={isHidden ? '•'.repeat(apikey.length) : apikey}
          className='ApiKey__input'
        />
        <button type='button' onClick={() => onVisibilityButtonClick(apikey)} className='ApiKey__btn' ><i className={`icon eye ${isHidden ? '' : 'slash'}`} /></button>
        <button type='button' onClick={() => copy(apikey)} className='ApiKey__btn ApiKey__btn_copy'><i className='icon copy' /></button>
      </form>
    </Fragment>
  )
}

export default ApiKey
