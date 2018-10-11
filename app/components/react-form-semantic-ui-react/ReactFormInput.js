import React, { Component } from 'react'
import { FormField } from 'react-form'
import { Input } from 'semantic-ui-react'

class ReactFormInput extends Component {
  componentWillMount () {
    const { fieldApi, initvalue = '' } = this.props
    fieldApi.setValue(initvalue)
  }

  componentDidMount () {
    if (this.props.autoFocus) {
      this.input.focus()
    }
  }

  render () {
    const { fieldApi, ...rest } = this.props
    const { setValue, setTouched, getValue } = fieldApi
    return (
      <Input
        value={getValue() || ''}
        onChange={e => setValue(e.target.value)}
        ref={input => {
          this.input = input
        }}
        onBlur={e => {
          if (e.target.value && e.target.value.length > 0) {
            setTouched()
          }
        }}
        {...rest}
      />
    )
  }
}

export default FormField(ReactFormInput)
