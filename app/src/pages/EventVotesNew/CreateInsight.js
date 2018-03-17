import React from 'react'
import 'medium-draft/lib/index.css'
import { convertToRaw } from 'draft-js'
import { draftjsToMd } from './../../utils/draftjsToMd'
import {
  Editor,
  createEditorState
} from 'medium-draft'
import CustomImageSideButton from './CustomImageSideButton'
import './CreateInsight.css'

export class CreateInsight extends React.Component {
  state = { // eslint-disable-line
    editorState: createEditorState() // for empty content
  }

  onChange = editorState => { // eslint-disable-line
    this.setState({ editorState })
    const markdown = draftjsToMd(convertToRaw(editorState.getCurrentContent()))
    if (markdown.length > 2) {
      this.props.changePost(markdown)
    }
  }

  componentDidMount () {
    this.refs.editor.focus()
  }

  render () {
    const { editorState } = this.state
    return (
      <Editor
        ref='editor'
        editorState={editorState}
        sideButtons={[{
          title: 'Image',
          component: CustomImageSideButton
        }]}
        toolbarConfig={{
          block: ['ordered-list-item', 'unordered-list-item'],
          inline: ['BOLD', 'UNDERLINE', 'hyperlink']
        }}
        placeholder='Write your insights here...'
        onChange={this.onChange} />
    )
  }
}

export default CreateInsight
