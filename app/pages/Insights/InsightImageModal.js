import React from 'react'
import { Modal } from 'semantic-ui-react'
import './InsightImageModal.css'

const InsightImageModal = ({ pic, onInsightImageModalClose }) => {
  return (
    pic && (
      <Modal
        defaultOpen
        closeIcon
        basic
        className='InsightImageModal'
        onUnmount={onInsightImageModalClose}
      >
        <Modal.Content>
          <img src={pic} alt='Modal pic' className='InsightImageModal__pic' />
        </Modal.Content>
      </Modal>
    )
  )
}

export default InsightImageModal
