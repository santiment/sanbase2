import React from 'react'
import {Modal} from 'semantic-ui-react'
import './InsightImageModal.css'

const InsightImageModal = ({pic}) => {
  return (
    <Modal defaultOpen closeIcon basic className='InsightImageModal' style={{width: 'auto'}}>
      <Modal.Content>
        <img src={pic} alt='Modal pic' />
      </Modal.Content>
    </Modal>
  )
}

export default InsightImageModal
