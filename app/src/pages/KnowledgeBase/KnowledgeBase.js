import React, { Component } from 'react'
import KnowledgeBaseGetStarted from '../../components/KnowledgeBase/KnowledgeBaseGetStarted'
import KnowledgeBaseBuyStakeSAN from '../../components/KnowledgeBase/KnowledgeBaseBuyStakeSAN'

class KnowledgeBase extends Component {
  // componentDidMount () {
  //   if (this.$ref) {
  //     this.$ref.scrollIntoView({
  //       // optional params
  //       // behaviour: 'smooth',
  //       block: 'start',
  //       inline: 'center'
  //     })
  //   }
  // }

  render () {
    return (
      // This is the div you want to scroll to
      <div
        ref={ref => {
          this.$ref = ref
        }}
      >
        <KnowledgeBaseGetStarted id='get-started' />
        <KnowledgeBaseBuyStakeSAN id='buy-stake-san' />
      </div>
    )
  }
}

export default KnowledgeBase
