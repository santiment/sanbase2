import React from 'react'
import KnowledgeBaseSection from './KnowledgeBaseSection'
import KnowledgeBaseBuyStakeSANLeft from './KnowledgeBaseBuyStakeSAN/KnowledgeBaseBuyStakeSANLeft'
import KnowledgeBaseBuyStakeSANRight from './KnowledgeBaseBuyStakeSAN/KnowledgeBaseBuyStakeSANRight'
import styles from './KnowledgeBaseBuyStakeSAN.module.scss'

const KnowledgeBaseBuyStakeSAN = ({ id }) => {
  return (
    <KnowledgeBaseSection
      id={id}
      title='Buy &amp; Stake SAN'
      lastUpdated='11-17-18'
    >
      <div className={styles.content}>
        <KnowledgeBaseBuyStakeSANLeft />
        <KnowledgeBaseBuyStakeSANRight />
      </div>
    </KnowledgeBaseSection>
  )
}

export default KnowledgeBaseBuyStakeSAN
