import React, { Component } from 'react'
import nprogress from 'nprogress'
import { convertToRaw } from 'draft-js'
import { compose, withState } from 'recompose'
import { Editor, createEditorState } from 'medium-draft'
import mediumDraftExporter from 'medium-draft/lib/exporter'
import mediumDraftImporter from 'medium-draft/lib/importer'
import { sanitizeMediumDraftHtml } from './../../utils/utils'
import CustomImageSideButton from './CustomImageSideButton'
import './CreateInsight.css'
import 'medium-draft/lib/index.css'

export class CreateInsight extends Component {
  constructor (props) {
    super(props)

    this.state = {
      editorState: createEditorState(
        convertToRaw(mediumDraftImporter(this.props.initValue))
      )
    }
  }

  onChange = editorState => {
    this.setState({ editorState })
    const renderedHTML = sanitizeMediumDraftHtml(
      mediumDraftExporter(editorState.getCurrentContent())
    )
    this.props.changePost(renderedHTML)
  }

  componentDidMount () {
    this.refs.editor.focus()
  }

  componentWillReceiveProps (nextProps) {
    if (nextProps.isPendingImg) {
      nprogress.start()
    }
    if (nextProps.isSuccessImg) {
      nprogress.done()
    }
  }

  render () {
    const { editorState } = this.state
    return (
      <Editor
        ref='editor'
        editorState={editorState}
        sideButtons={[
          {
            title: 'Image',
            component: CustomImageSideButton,
            props: {
              onPendingImg: this.props.onPendingImg,
              onErrorImg: this.props.onErrorImg,
              onSuccessImg: this.props.onSuccessImg
            }
          }
        ]}
        toolbarConfig={{
          block: ['ordered-list-item', 'unordered-list-item'],
          inline: ['BOLD', 'UNDERLINE', 'hyperlink']
        }}
        placeholder='Write your insights here...'
        onChange={this.onChange}
      />
    )
  }
}

export default compose(
  withState('isPendingImg', 'onPendingImg', false),
  withState('isErrorImg', 'onErrorImg', false),
  withState('isSuccessImg', 'onSuccessImg', false)
)(CreateInsight)
