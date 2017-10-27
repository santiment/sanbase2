export default (props) => (
  <div className="row">
    <div className="col-lg-12">
      <h1>{ props.name }</h1>
      <p style={{'marginLeft': '16px'}}>{ props.description }</p>
    </div>
  </div>
)
