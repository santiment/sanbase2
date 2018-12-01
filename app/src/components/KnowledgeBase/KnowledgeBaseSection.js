import React from 'react'
import styles from './KnowledgeBaseSection.module.scss'

const KnowledgeBaseSection = ({
  id,
  title,
  lastUpdated,
  render,
  children = render
}) => {
  return (
    <section id={id} className={styles.section}>
      <h2 className={styles.title}>{title}</h2>
      {lastUpdated && (
        <h4 className={styles.updated}>Last updated: {lastUpdated}</h4>
      )}
      <div className={styles.content}>{children}</div>
    </section>
  )
}

export default KnowledgeBaseSection
