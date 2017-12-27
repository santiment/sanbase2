SANBASE Frontend App

## For Developers

1. fork this repo
2. `yarn`
3. `yarn start` or `mix phx.server`
4. Before push changes, run `yarn test`

Run tests `yarn test` (this command not run test with watcher, if you want this
run testing with test:js command)

Run test js: `npm run test:js`
Run linting js: `npm run test:lint:js`
Run linting css: `npm run test:lint:css`

If you need to update snapshots, you should run test js with command
`npm run test:js` and if any snapshot is failed, press `u`.

We use JEST, enzyme and jest snapshots for testing.

We use **standard** for js lint and **stylelint** for css.
