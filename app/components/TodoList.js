import Layout from '../components/Layout.js'

export default (props) => (
  <ul className="todo_list">
    {props.items.map((item) => (
      <li key={item}>
        {item}
      </li>
    ))}
  </ul>
)
