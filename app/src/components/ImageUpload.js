import React from 'react'
import gql from 'graphql-tag'
import { graphql } from 'react-apollo'

export default graphql(gql`
  mutation($images: [Upload!]!) {
    uploadImage(images: $images) {
      contentHash
      fileName
      imageUrl
      hashAlgorithm
    }
  }
`)(({ mutate }) => (
  <input
    type='file'
    multiple
    required
    onChange={({ target: { validity, files } }) => {
      console.log(files)
      validity.valid &&
        mutate({ variables: { images: files } }).then((...rest) => {
          console.log(rest)
        })
    }}
  />
))
