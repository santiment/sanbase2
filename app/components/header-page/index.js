export default ({ description, name }) => (
  <div className="row">
    <div className="col-lg-12">
      <h1>{ name }</h1>
      <p>{ description }</p>
    </div>
    <style jsx>{`
      p {
        margin-left: 16px;
      }
    `}</style>
  </div>
)
