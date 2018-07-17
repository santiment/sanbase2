import gql from 'graphql-tag'
import { graphql } from 'react-apollo'
import Raven from 'raven-js'
import { ImageSideButton, Block, addNewBlock } from 'medium-draft'

class CustomImageSideButton extends ImageSideButton {
  onChange (e) {
    const file = e.target.files[0]
    if (file.type.indexOf('image/') === 0) {
      this.props.onPendingImg(true)
      this.props
        .mutate({ variables: { images: e.target.files } })
        .then(rest => {
          this.props.onPendingImg(false)
          this.props.onSuccessImg(true)
          const imageData = rest['data'].uploadImage[0]
          const uploadImageUrl = imageData ? imageData.imageUrl : null
          this.props.setEditorState(
            addNewBlock(this.props.getEditorState(), Block.IMAGE, {
              src: uploadImageUrl
            })
          )
        })
        .catch(error => {
          this.props.onErrorImg(true)
          Raven.captureException(error)
        })
    }
    this.props.close()
  }
}

export default graphql(gql`
  mutation($images: [Upload!]!) {
    uploadImage(images: $images) {
      contentHash
      fileName
      imageUrl
      hashAlgorithm
    }
  }
`)(CustomImageSideButton)
