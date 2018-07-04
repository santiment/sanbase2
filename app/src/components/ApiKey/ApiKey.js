import React, {Fragment} from 'react'

const ApiKey = ({apikey, isHidden, onVisibilityButtonClick}) => {
  return (
    <Fragment>
      <p>
        Your API key is: {isHidden ? '***' : apikey}
      </p>
      <button type="button" onClick={() => onVisibilityButtonClick(apikey)} >{isHidden ? 'REVEAL' : 'HIDE'}</button>
    </Fragment>
  )
}

export default ApiKey
