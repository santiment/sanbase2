import React from 'react'
import 'medium-draft/lib/index.css'
import './CreateInsight.css'

import {
  Editor,
  Block,
  addNewBlock,
  createEditorState,
  ImageSideButton
} from 'medium-draft'

class CustomImageSideButton extends ImageSideButton {
  onChange (e) {
    const file = e.target.files[0]
    if (file.type.indexOf('image/') === 0) {
      console.log(file)
      this.props.setEditorState(addNewBlock(
        this.props.getEditorState(),
        Block.IMAGE, {
          src: file
        }
      ))
    }
    this.props.close()
  }
}

export class CreateInsight extends React.Component {
  state = { // eslint-disable-line
    editorState: createEditorState() // for empty content
  }

  onChange = editorState => { // eslint-disable-line
    this.setState({ editorState })
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
