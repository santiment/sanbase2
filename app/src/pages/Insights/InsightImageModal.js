import React from 'react'
import {Modal} from 'semantic-ui-react'
import './InsightImageModal.css'

const InsightImageModal = ({pic, onInsightImageModalClose}) => {
  return (
    <Modal defaultOpen closeIcon basic className='InsightImageModal' style={{width: 'auto'}} onUnmount={onInsightImageModalClose}>
      <Modal.Content>
        <img src={pic} alt='Modal pic' />
      </Modal.Content>
    </Modal>
  )
}

export default InsightImageModal
